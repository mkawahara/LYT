# Requires `/common`  
# Requires `/support/lyt/loader`  
# Requires `/models/member/settings`
# -------------------

# This module handles playback of current media and timing of transcript updates  
# TODO: provide a visual cue on the next and previous section buttons if there are no next or previous section.

LYT.player = 
  ready: false 
  el: null
  
  book: null #reference to an instance of book class
  nextButton: null
  previousButton: null
  playing: null
  refreshTimer: null
  
  # TODO See if the IOS metadata bug has been fixed here:
  # https://github.com/happyworm/jPlayer/commit/2889b5efd84c4920d904e7ab368aa8db95929a95
  # https://github.com/happyworm/jPlayer/commit/de22c88d4984210dd1bf4736f998d693c097cba6
  
  playBackRate: 1
  
  lastBookmark: (new Date).getTime()

  playlist: -> @book?.playlist
  
  segment: -> @playlist().currentSegment
  
  section: -> @playlist().currentSection()
  
  init: ->
    log.message 'Player: starting initialization'
    @el = jQuery("#jplayer")
    @nextButton = jQuery("a.next-section")
    @previousButton = jQuery("a.previous-section")
    @playBackRate = LYT.settings.get('playBackRate') if LYT.settings.get('playBackRate')?

    jplayer = @el.jPlayer
      ready: =>
        LYT.instrumentation.record 'ready', @getStatus()
        log.message "Player: event ready: paused: #{@getStatus().paused}"
        @ready = true
        log.message 'Player: initialization complete'
        
        $.jPlayer.timeFormat.showHour = true
        
        # Pause button is only shown when playing
        $('.lyt-pause').click =>
          @stop()

        $('.lyt-play').click => 
          @play()
        
        @nextButton.click =>
          log.message "Player: next: #{@segment().next?.url()}"
          @nextSegment()
            
        @previousButton.click =>
          log.message "Player: previous: #{@segment().previous?.url()}"
          @previousSegment()

        Mousetrap.bind 'alt+ctrl+space', =>
          if @playing 
            $('.jp-pause').click()
          else 
            $('.jp-play').click()
          return false

        Mousetrap.bind 'alt+right', ->
          $('a.next-section').click()
          return false
        
        Mousetrap.bind 'alt+left', ->
          $('a.previous-section').click()
          return false
      
        # FIXME: add handling of section jumps
        Mousetrap.bind 'alt+ctrl+n', ->
          log.message "next section"
          return false

        Mousetrap.bind 'alt+ctrl+o', ->
          log.message "previous section"
          return false


      loadstart: (event) =>
        LYT.instrumentation.record 'loadstart', event.jPlayer.status
      
      ended: (event) =>
        LYT.instrumentation.record 'ended', event.jPlayer.status
      
      play: (event) =>
        LYT.instrumentation.record 'play', event.jPlayer.status
# TODO: [play-controllers]: test and see if this issue has reappeared and find
#       out if this documentation needs to be moved elsewhere.
#
#        status = event.jPlayer.status
#        log.message "Player: event play, nextOffset: #{@nextOffset}, currentTime: #{status.currentTime}"
#        if @nextOffset?
#          # IOS will some times omit seeking (both the actual seek and the
#          # following seeked event are missing) and just start playing from
#          # the start of the stream. We detect this here and do another seek
#          # if it is the case.
#          # This will cause a loop if the play event arrives later than 0.5
#          # seconds after playback has started.
#          if -0.01 < status.currentTime - @nextOffset < 0.5
#            # This event handler consumes @nextOffset
#            @nextOffset = null
#          else
#            log.warn "Player: event play: retry seek, nextOffset: #{@nextOffset}, currentTime: #{status.currentTime}"
#            # Stop playback to ensure that another play event is emitted
#            # to check that the player doesn't skip the next seek as well.
#            @el.jPlayer 'pause'
#            # Not using a delay here seems to create infinite play/pause loops
#            # because the player doesn't get time for the seek.
#            # (This is probably a hint wrt a better way of working around this
#            # bug in IOS.)
#            setTimeout(
#              => @el.jPlayer 'play', @nextOffset
#              500
#            )
#            return
        
      pause: (event) =>
        LYT.instrumentation.record 'pause', event.jPlayer.status

      seeked: (event) =>
        LYT.instrumentation.record 'seeked', event.jPlayer.status
          
      loadedmetadata: (event) =>
        LYT.instrumentation.record 'loadedmetadata', event.jPlayer.status
# TODO: [play-controllers]: test and see if this issue has reappeared and find
#       out if this documentation needs to be moved elsewhere.
#        log.message "Player: loadedmetadata: playAttemptCount: #{@playAttemptCount}, firstPlay: #{@firstPlay}, paused: #{@getStatus().paused}"
#        LYT.loader.set('Loading sound', 'metadata') if @playAttemptCount == 0 and @firstPlay
#        # Bugs in IOS 5 and IOS 6 forces us to keep trying to load the media
#        # file until we get a valid duration.
#        # At this point we get the following sporadic errors
#        # IOS 5: duration is not a number.
#        # IOS 6: duration is set to zero on non-zero length audio streams
#        # Caveat emptor: for this reason, the player will wrongly assume that
#        # there is an error if the player is ever asked to play a zero length
#        # audio stream.
#        if @getStatus().src == @currentAudio
#          if event.jPlayer.status.duration == 0 or isNaN event.jPlayer.status.duration
#            if @playAttemptCount <= LYT.config.player.playAttemptLimit
#              @el.jPlayer 'setMedia', {mp3: @currentAudio}
#              @playAttemptCount = @playAttemptCount + 1
#              log.message "Player: loadedmetadata, play attempts: #{@playAttemptCount}"
#              return
#            # else: give up - we pretend that we have got the duration
#          @playAttemptCount = 0
#        # else: nothing to do because we are playing the wrong file
      
      canplay: (event) =>
        LYT.instrumentation.record 'canplay', event.jPlayer.status

      canplaythrough: (event) =>
        LYT.instrumentation.record 'canplaythrough', event.jPlayer.status
# TODO: [play-controllers]: see if we need to set playback rate here (shouldn't
#       be necessary.
      
      error: (event) =>
        LYT.instrumentation.record 'error', event.jPlayer.status
        switch event.jPlayer.error.type
          when $.jPlayer.error.URL
            log.message "Player: event error: jPlayer: url error: #{event.jPlayer.error.message}, #{event.jPlayer.error.hint}, #{event.jPlayer.status.src}"
            parameters =
              mode:                'bool'
              prompt:              LYT.i18n('Unable to retrieve sound file')
              subTitle:            LYT.i18n('')
              animate:             false
              useDialogForceFalse: true
              allowReopen:         true
              useModal:            true
              buttons:             {}
            parameters.buttons[LYT.i18n('Try again')] =
              click: -> window.location.reload()
              theme: 'c'
            parameters.buttons[LYT.i18n('Cancel')] =
              click: -> $.mobile.changePage LYT.config.defaultPage.hash
              theme: 'c'
            LYT.render.showDialog($.mobile.activePage, parameters)

            #reopen the dialog...
            #TODO: this is usually because something is wrong with the session or the internet connection, 
            # tell people to try and login again, check their internet connection or try again later
          when $.jPlayer.error.NO_SOLUTION
            log.message 'Player: event error: jPlayer: no solution error, you need to install flash or update your browser.'
            parameters =
              mode:                'bool'
              prompt:              LYT.i18n('Platform not supported')
              subTitle:            LYT.i18n('')
              animate:             false
              useDialogForceFalse: true
              allowReopen:         true
              useModal:            true
              buttons:             {}
            parameters.buttons[LYT.i18n('OK')] =
              click: ->
                $(document).one 'pagechange', -> $.mobile.silentScroll $('#supported-platforms').offset().top
                $.mobile.changePage '#support'
              theme: 'c'
            LYT.render.showDialog($.mobile.activePage, parameters)
      
      swfPath: "./lib/jPlayer/"
      supplied: "mp3"
      solution: 'html, flash'

  # Be cautious only read from the returned status object
  getStatus: -> @el.data('jPlayer').status

  # TODO: Remove our own playBackRate attribute and use the one on the jPlayer
  #       If it isn't available, there is no reason to try using it.
  setPlayBackRate: (playBackRate) ->
    if playBackRate?
      @playBackRate = playBackRate
      
    # TODO: [play-controllers] integrate the setting playback rate this with
    #       the play() method by adding a playback rate to the play command
    setRate = =>
      @el.data('jPlayer').htmlElement.audio.playbackRate = @playBackRate
      @el.data('jPlayer').htmlElement.audio.defaultPlaybackRate = @playBackRate

    unsetRate = =>
      @el.data('jPlayer').htmlElement.audio.playbackRate = null
      @el.data('jPlayer').htmlElement.audio.defaultPlaybackRate = null

    setRate()

    # Added for IOS6: iphone will not change the playBackRate unless you pause
    # the playback, after setting the playbackRate. And then we can obtain the new
    # playbackRate and continue
    # TODO: This makes safari desktop version fail...so find a solution...browser sniffing?
    
    @el.jPlayer 'pause'
    setRate()
    
    # Return before starting the player unless we are supposed so
    # This is definately a hack that should go away if we move everyting to
    # player-controllers, because setting playback rate should be done as an
    # integral part of starting playback.
    return unless @playing
    
    @el.jPlayer 'play'

    # Added for Safari desktop version - will not work unless rate is unset
    # and set again
    unsetRate()
    setRate()

    log.message "Player: setPlayBackRate: #{@playBackRate}"
  
  refreshContent: ->
    # Using timeout to ensure that we don't call updateHtml too often
    refreshHandler = => @updateHtml segment if @playlist() and segment = @segment()
    clearTimeout @refreshTimer if @refreshTimer
    @refreshTimer = setTimeout refreshHandler, 500
      
 # Update player content with provided segment
  updateHtml: (segment) ->
    if not segment?
      log.error "Player: updateHtml called with no segment"
      return

    if segment.state() isnt 'resolved'
      log.error "Player: updateHtml called with unresolved segment"
      return

    log.message "Player: updateHtml: rendering segment #{segment.url()}, start #{segment.start}, end #{segment.end}"
    LYT.render.textContent segment
    segment.preloadNext()
  
  # Register callback to call when jPlayer is ready
  whenReady: (callback) ->
    if @ready
      callback()
    else
      @el.bind $.jPlayer.event.ready, callback

  # Load a book and seek to position provided by:  
  # url:        url pointing to par or seq element in SMIL file.
  # smilOffset: SMIL offset relative to url.
  # play:       flag indicating if the book should start playing after loading
  #             has finished.
  load: (book, url = null, smilOffset, play) ->
    log.message "Player: Load: book #{book}, segment #{url}, smilOffset: #{smilOffset}, play #{play}"

    # Wait for jPlayer to get ready
    ready = jQuery.Deferred()
    @whenReady -> ready.resolve()
  
    # Get the right book  
    result = ready.then =>
      if book is @book?.id
        jQuery.Deferred().resolve @book
      else
        # Load the book since we haven't loaded it already
        LYT.Book.load book

    # Now seek to the right point in the book
    result = result.then (book) =>
      jQuery("#book-duration").text book.totalTime
      # Setting @book should be done after seeking has completed, but the
      # dependency on the books playlist prohibits this.
      @book = book
      if not url and book.lastmark?
        url = book.lastmark.URI
        smilOffset = book.lastmark.timeOffset
        log.message "Player: resuming from lastmark #{url}, smilOffset #{smilOffset}"

      # TODO: [play-controllers] Test all various cases of this structure and
      #       see if it can be simplified.
      # TODO: [play-controllers] Make sure to call updateHtml once book-player
      #       is displayed.
      promise = null
      if url
        promise = @playlist().segmentByURL url
        promise = promise.then(
            (segment) =>
              offset = segment.audioOffset(smilOffset) if smilOffset
              @seekSegmentOffset segment, offset
            (error) =>
              if url.match /__LYT_auto_/
                log.message "Player: failed to load #{url} containing auto generated book marks - rewinding to start"
              else
                log.error "Player: failed to load url #{url}: #{error} - rewinding to start"
              @playlist().rewind()
          )
      else
        promise = @playlist().rewind()
        promise = promise.then (segment) => @seekSegmentOffset segment, 0
      
      promise.fail ->
        deferred.reject 'failed to find segment'
        log.error "Player: failed to find segment"

      if play
        promise.done => @play()

      promise.then (segment) -> jQuery.Deferred().resolve book
    
    result.fail (error) ->
      log.error "Player: failed to load book, reason #{error}"
      deferred.reject error

    LYT.loader.register 'Loading sound', result.promise()
    
    result.promise()

  # This is a public method - stops playback
  # The stop command returns the last play command or null in case there
  # isn't any.
  stop: ->
    log.message 'Player: stop'
    # TODO: [play-controllers] make this work again:
    # LYT.render.setPlayerButtonFocus 'play'

    @playing = false
    if command = @playCommand
      command.done => @playCommand = null if @playCommand is command
      command.cancel()
    
    return command

  # Starts playback
  play: ->
    log.message "Player: play"
    # TODO: [play-controllers] make this work again:
    # LYT.render.setPlayerButtonFocus 'pause'

    command = null
    getPlayCommand = =>
      command = new LYT.player.command.play @el
      stopHandler = ->
        log.message 'Got stop event'
        command.cancel()
      $(this).one 'playback:stop', stopHandler
      command.progress progressHandler
      command.done -> log.group 'Play completed. ', command.status()
      command.always ->
        $(this).off 'playback:stop', stopHandler
        $('.lyt-pause').hide()
        $('.lyt-play').show()

    nextSegment = null
    progressHandler = (status) =>
      
      $('.lyt-play').hide()
      $('.lyt-pause').show()
  
      time = status.currentTime
      
      # FIXME: Pause due unloaded segments should be improved with a visual
      #        notification.
      # FIXME: Handling of resume when the segment has been loaded can be
      #        mixed with user interactions, causing an undesired resume
      #        after the user has clicked pause.
  
      # Don't do anything else if we're already moving to a new segment
      if nextSegment?.state() is 'pending'
        log.message 'Player: play: progress: nextSegment set and pending.'
        log.message "Player: play: progress: Next segment: #{nextSegment.state()}. Pause until resolved."
        return
      
      # This method is idempotent - will not do anything if last update was
      # recent enough.
      @updateLastMark()
  
      # Move one segment forward if no current segment or no longer in the
      # interval of the current segment and within two seconds past end of
      # current segment (otherwise we are seeking ahead).
      segment = @segment()
      if segment? and status.src == segment.audio and segment.start < time + 0.1 < segment.end + 2
        if time < segment.end
          # Segment and audio are in sync
          @lastplayed =
            book:    segment.section.nccDocument.book.id
            section: segment.section.url
            segment: segment.id
            offset:  time
            updated: new Date()
        else
          # Segment and audio are not in sync, move to next segment
          # This block uses the current segment for synchronization.
          log.message "Player: play: progress: queue for offset #{time}"
          log.message "Player: play: progress: current segment: [#{segment.url()}, #{segment.start}, #{segment.end}, #{segment.audio}], no segment at #{time}, skipping to next segment."
          nextSegment = @playlist().nextSegment segment
          timeoutHandler = =>
            LYT.loader.register 'Loading book', nextSegment
            command.cancel()
            nextSegment.done => getPlayCommand()
            nextSegment.fail -> log.error 'Player: play: progress: unable to load next segment after pause.'
          timer = setTimeout timeoutHandler, 1000
          nextSegment.done (next) =>
            clearTimeout timer
            if next?
              if next.audio is status.src and next.start - 0.1 < time < next.end + 0.1
                # Audio has progressed to next segment, so just update
                @playlist.currentSegment = next
                @updateHtml next
              else
                # The segment next requires a seek and maybe loading a
                # different audio stream.
                log.message 'Player: play: progress: switching audio file: playSegment #{next.url()}'
                # This stops playback and should ensure that we won't skip more
                # than one segment ahead if this progressHandler is called
                # again. Once playback has stopped, play the segment next.
                command.always => @playSegment next
                command.cancel()
            else
              command.cancel()
              LYT.render.bookEnd()
              log.message 'Player: play: book has ended'
      else
        # This block uses the current offset in the audio stream for
        # synchronization - a strategy that fails if there is no segment for
        # the current offset.
        log.group "Player: play: progress: segment and sound out of sync. Fetching segment for #{status.src}, offset #{time}", status
        if segment
          log.group "Player: play: progress: current segment: [#{segment.url()}, #{segment.start}, #{segment.end}, #{segment.audio}]: ", segment
        else
          log.message 'Player: play: progress: no current segment set.'
        nextSegment = @playlist().segmentByAudioOffset status.src, time
        nextSegment.fail (error) ->
          # TODO: The user may have navigated to a place in the audio stream
          #       that isn't included in the book. Handle this gracefully by
          #       searching for the next segment in the audio file.
          log.error "Player: play: progress: Unable to load next segment: #{error}."
        nextSegment.done (next) =>
          if next
            log.message "Player: play: progress: (#{status.currentTime}s) moved to #{next.url()}: [#{next.start}, #{next.end}]"
            @updateHtml next
          else
            log.error "Player: play: progress: Unable to load any segment for #{status.src}, offset #{time}."

    @playing = true
    result = jQuery.Deferred()
    if oldCommand = @playCommand
      # We need to cancel the previous play command before doing anything else
      # The command may either resolve or reject depending on which event hits
      # first: our cancel call or end of audio stream.
      oldCommand.always -> result.resolve()
      oldCommand.cancel()
    else
      result.resolve()
    result = result.then => @playCommand = getPlayCommand()
    result

  seekSegmentOffset: (segment, offset) ->
    log.message "Player: seekSegmentOffset: play #{segment.url?()}, offset #{offset}"

    segment or= @segment()
    
    result = jQuery.Deferred().resolve()
    if @playCommand and @playCommand.state is 'pending'
      # Stop playback and ensure that this part of the deferred chain resolves
      # once playback has stopped
      result = result.then =>
        @stop().then(
          -> jQuery.Deferred().resolve()
          -> jQuery.Deferred().resolve()
        )

    # See if we need to initiate loading of a new audio file
    result = result.then => segment
    result = result.then (segment) =>
      if @getStatus().src != segment.audio
        log.message "Player: seekSegmentOffset: load #{segment.audio}"
        (new LYT.player.command.load @el, segment.audio).then -> segment
      else
        jQuery.Deferred().resolve segment

    # Now move the play head
    result = result.then (segment) =>
      # Ensure that offset has a useful value
      if offset?
        if offset > segment.end
          log.warn "Player: seekSegmentOffset: got offset out of bounds: segment end is #{segment.end}"
          offset = segment.end - 1
          offset = segment.start if offset < segment.start
        else if offset < segment.start
          log.warn "Player: seekSegmentOffset: got offset out of bounds: segment start is #{segment.start}"
          offset = segment.start
      else
        offset = segment.start
      if offset - 0.1 < @getStatus().currentTime < offset + 0.1
        # We're already at the right point in the audio stream
        jQuery.Deferred().resolve segment
      else
        # Not at the right point - seek
        (new LYT.player.command.seek @el, offset).then -> segment

    # Once the seek has completed, render the segment
    result.done (segment) => @updateHtml segment

    result

  playSegment: (segment) -> @playSegmentOffset segment, null
  
  # Will display the provided segment, load (if necessary) and play the
  # associated audio file starting att offset. If offset isn't provided, start
  # at the beginning of the segment. It is an error to provide an offset not 
  # within the bounds of segment.start and segment.end. In this case, the
  # offset is capped to segment.start or segment.end - 1 (one second before
  # the segment ends).
  playSegmentOffset: (segment, offset) ->
    # If play is set to true or false, set playing accordingly
    @playing = true
    @seekSegmentOffset(segment, offset).then => @play()

  dumpStatus: -> log.message field + ': ' + LYT.player.getStatus()[field] for field in ['currentTime', 'duration', 'ended', 'networkState', 'paused', 'readyState', 'src', 'srcSet', 'waitForLoad', 'waitForPlay']

  # If it seems that loading the provided segment will take time
  # display the loading message and pause the player.
  # Not providing a segment is allowed and will cause the loading
  # message to appear and the player to pause.
  setMetadataLoader: (segment) ->
#    if not segment or (segment.state() isnt 'resolved' or segment.audio isnt @currentAudio)
#      # Using a delay and the standard fade duration on LYT.loader.set is the
#      # most desirable, but Safari on IOS blocks right after it starts loading
#      # the sound, which means that the message appears very late.
#      # This is why we use fadeDuration 0 below.
#      LYT.loader.set 'Loading sound', 'metadata', true, 0
#      @el.jPlayer 'pause'

  navigate: (segmentPromise) ->
    
    handler = null
    if @playing
      handler = =>
        @playSegment segmentPromise
        segmentPromise
    else
      handler = =>
        @seekSegmentOffset segmentPromise
        segmentPromise

    if @playCommand
      # Stop playback and set up both done and fail handlers
      @playCommand.cancel()
      @playCommand.then handler, handler
    else
      handler()

  # Skip to next segment
  # Returns segment promise
  nextSegment: ->
    return unless @playlist()?
    if @playlist().hasNextSegment() is false
      LYT.render.bookEnd()
      delete @book.lastmark
      @book.saveBookmarks()
      return
    @navigate @playlist().nextSegment()

  # Skip to next segment
  # Returns segment promise
  previousSegment: ->
    return unless @playlist()?.hasPreviousSegment()
    @navigate @playlist().previousSegment()
  
  updateLastMark: (force = false, segment) ->
    return unless LYT.session.getCredentials() and LYT.session.getCredentials().username isnt LYT.config.service.guestLogin
    return unless (segment or= @segment())
    segment.done (segment) =>
      # We use wall clock time here because book time can be streched if
      # the user has chosen a different play back speed.
      now = (new Date).getTime()
      interval = LYT.config.player?.lastmarkUpdateInterval or 10000
      return if not (force or @lastBookmark and now - @lastBookmark > interval)
      # Round off to nearest 5 seconds
      # TODO: Use segment start if close to it
      @book.setLastmark segment, Math.floor(@getStatus().currentTime / 5) * 5
      @lastBookmark = now

  getCurrentlyPlaying: ->
    # Only return something if we have played it recently
    if lastplayed = @lastplayed
      return lastplayed if new Date() - lastplayed.updated < 10000
