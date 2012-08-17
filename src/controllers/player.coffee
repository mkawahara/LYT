# Requires `/common`  
# Requires `/support/lyt/loader`  

# -------------------

# This module handles playback of current media and timing of transcript updates  
# TODO: provide a visual cue on the next and previous section buttons if there are no next or previous section.

LYT.player = 
  SILENTMEDIA: "http://m.nota.nu/sound/dixie.mp3" # FIXME: dixie chicks as we test, replace with silent mp3 when moving to production
  PROGRESSION_MODES:
    MP3:  'mp3'
    TEXT: 'text'
  
  ready: false 
  el: null
  
  time: ""
  book: null #reference to an instance of book class
  playlist: -> @book?.playlist
  nextButton: null
  previousButton: null
  playIntentOffset: 0

  autoProgression: true 
  toggleAutoProgression: null
  progressionMode: null
  timeupdateLock: false
  
  fakeEndScheduled: false
  
  # TODO See if the IOS metadata bug has been fixed here:
  # https://github.com/happyworm/jPlayer/commit/2889b5efd84c4920d904e7ab368aa8db95929a95
  # https://github.com/happyworm/jPlayer/commit/de22c88d4984210dd1bf4736f998d693c097cba6
  _iBug: false
  
  playAttemptCount: 0
  gotDuration : null
  playBackRate : 1 #Default playBackRate for audio element....
  
  
  lastBookmark: (new Date).getTime()
  
  segment: -> @playlist().currentSegment
  
  section: -> @playlist().currentSection()
  
  init: ->
    log.message 'Player: starting initialization'
    # Initialize jplayer and set ready True when ready
    @el = jQuery("#jplayer")
    @nextButton = jQuery("a.next-section")
    @previousButton = jQuery("a.previous-section")
    @progressionMode = @PROGRESSION_MODES.MP3
    @currentAudio = ''
         
    jplayer = @el.jPlayer
      ready: =>
        @ready = true
        @timeupdateLock = false
        log.message 'Player: initialization complete'
        #@el.jPlayer('setMedia', {mp3: @SILENTMEDIA})
        #todo: add a silent state where we do not play on can play   
        
        $.jPlayer.timeFormat.showHour = true
        
        @nextButton.click =>
          log.message "Player: next: #{@segment().next?.url()}"
          @nextSegment @autoProgression
            
        @previousButton.click =>
          log.message "Player: previous: #{@segment().previous?.url()}"
          @previousSegment @autoProgression
      
      timeupdate: (event) =>
        status = event.jPlayer.status
        @time = status.currentTime

        # FIXME: Pause due unloaded segments should be improved with a visual
        #        notification.
        # FIXME: Handling of resume when the segment has been loaded can be
        #        mixed with user interactions, causing an undesired resume
        #        after the user has clicked pause.

        # Don't do anything else if we're already moving to a new segment
        if @timeupdateLock and @_next and @_next.state() isnt 'resolved'
          log.message "Player: timeupdate: timeupdateLock set. Next segment: #{@_next.state()}. Pause until resolved."
          @pause()
          @_next.done => @el.jPlayer('play')
          return

        # Move one segment forward if no current segment or no longer in the
        # interval of the current segment
        if not @segment() or status.src != @segment().audio or @segment().end < @time
          log.message "Player: timeupdate: queue for offset #{@time}"
          @timeupdateLock = true
          next = @playlist().segmentByAudioOffset status.src, @time
          @_next = next
          next.fail -> log.errorGroup 'Player: timeupdate event: Unable to load next segment.', next
          next.done (next) =>
            if next
              log.message "Player: timeupdate: (#{status.currentTime}s) moved to #{next.url()}: [#{next.start}, #{next.end}]"
              @updateHtml next
            else
              log.message "Player: timeupdate: (#{status.currentTime}s): no current segment"
          next.always => @timeupdateLock = false

      loadstart: (event) =>
        log.message 'Player: load start'
        @setPlayBackRate()
        @timeupdateLock = false
        if(@playAttemptCount < 1 and ($.jPlayer.platform.iphone or $.jPlayer.platform.ipad or $.jPlayer.platform.iPod))
          if (!LYT.config.player.IOSFirstPlay and $.mobile.activePage[0].id is 'book-play')
            # IOS will not AutoPlay...
            LYT.loader.set('Loading sound', 'metadata') 

        else if(@playAttemptCount < 1 and $.mobile.activePage[0].id is 'book-play')
          #Only make the loading sign the first time...
          LYT.loader.set('Loading sound', 'metadata') 
        
        return if $.jPlayer.platform.android

        return if ($.jPlayer.platform.iphone or $.jPlayer.platform.ipad or $.jPlayer.platform.iPod)
        
        return unless jQuery.browser.webkit
        
        @updateHtml @segment()
      
      ended: (event) =>
        log.message 'Player: event ended'
        @timeupdateLock = false
        if @autoProgression
          log.message 'Player: event ended: moving to next segment'
          @nextSegment true
      
      play: (event) => @autoProgression = true
      
      pause: (event) =>
        status = event.jPlayer.status
        return if status.ended # Drop pause event emitted when media ends
        @autoProgression = false
        return unless @isIOS()
        if @_iBug
          log.warn 'we are ibug'
          #@el.jPlayer('load')
          
        else if status.duration > 0 and jQuery.jPlayer.convertTime(status.duration) is not 'NaN' and jQuery.jPlayer.convertTime(status.duration) is not '00:00' and (status.currentTime is 0 or status.currentTime is status.duration)  
          log.warn 'set ibug'
          @_iBug = true
          if @autoProgression
            @nextSegment true
                   
      seeked: (event) =>
        @time = event.jPlayer.status.currentTime
        log.message "Player: event seeked to offset #{@time}"
        @timeupdateLock = false
        LYT.loader.close('metadata')
        return if @seekedLoadSegmentLock
        segment = @playlist().segmentByAudioOffset event.jPlayer.status.src, @time
        segment.fail -> log.error 'Player: event seeked: unable to get segment at offset '
        segment.done (segment) => @updateHtml segment

      loadedmetadata: (event) =>
        log.message 'Player: loaded metadata'
        if isNaN( event.jPlayer.status.duration )
          #alert event.jPlayer.status.duration
          @gotDuration = false
          if(@getStatus().src == @currentAudio and @playAttemptCount <= LYT.config.player.playAttemptLimit)
            @el.jPlayer "setMedia", {mp3: @currentAudio}
            @el.jPlayer "load"
            @playAttemptCount = @playAttemptCount + 1 
            log.message "Player: loadedmetadata, play attempts: #{@playAttemptCount}"
          else if ( @playAttemptCount > LYT.config.player.playAttemptLimit)
            @gotDuration = true
            #faking that we got the duration - we don´t but need to play the file now...
            
        else
         @gotDuration = true
         @playAttemptCount = 0
         #LYT.loader.close('metadata')
         
      
      canplay: (event) =>
        log.message 'Player: event can play'
        if @gotDuration
          @gotDuration = false
          #@el.data('jPlayer').htmlElement.audio.currentTime = @playIntentOffset
          #@pause(@playIntentOffset)
          if @playIntentOffset? and @playIntentOffset > 0 and @isIOS()
            if LYT.config.player.IOSFirstPlay
              @pause()
          else
            LYT.loader.close('metadata')
        if(!@gotDuration?)
          LYT.loader.close('metadata') #windows phone 7

      
      canplaythrough: (event) =>
        log.message 'Player: event can play through'
        if @playIntentOffset? and @playIntentOffset > 0 and @isIOS()
          if LYT.config.player.IOSFirstPlay
            LYT.config.player.IOSFirstPlay = false;
            @el.data('jPlayer').htmlElement.audio.currentTime = @playIntentOffset
            @el.data('jPlayer').htmlElement.audio.play()
          else
            @pause(@playIntentOffset)

            LYT.loader.close('metadata')  
         
        else if LYT.config.player.IOSFirstPlay and @isIOS()
          LYT.config.player.IOSFirstPlay = false;

        
        #@el.data('jPlayer').htmlElement.audio.currentTime = parseFloat("6.4");
        #LYT.loader.close('metadata')
      
      progress: (event) =>
        #log.message 'Player: event progress'
        # To take advantage of this event, calculate how much audio has been
        # buffered by looking at the audio element owned by jPlayer.
        #LYT.loader.close('metadata')
      
      error: (event) =>
        switch event.jPlayer.error.type
          when $.jPlayer.error.URL
            log.message 'jPlayer: url error'
            $("#submenu").simpledialog({
                'mode' : 'bool',
                'prompt' : 'Der er opstået en fejl!',
                'subTitle' : 'kunne ikke hente lydfilen.'
                'animate': false,
                'useDialogForceFalse': true,
                'allowReopen': true,
                'useModal': true,
                'buttons' : {
                  'Prøv igen': 
                    click: (event) ->
                      window.location.reload()
                    ,
                    theme: "c"
                  ,
                  'Annuller': 
                    click: (event) ->
                      $.mobile.changePage "#bookshelf"
                    ,
                    theme: "c"
                  ,
                   
                }
              
            })
            #reopen the dialog...
            #TODO: this is usually because something is wrong with the session or the internet connection, 
            # tell people to try and login again, check their internet connection or try again later
          when $.jPlayer.error.NO_SOLUTION
            log.message 'jPlayer: no solution error, you need to install flash or update your browser.'
            #TODO: send people to a link where they can download flash or update their browser
      
      
      swfPath: "./lib/jPlayer/"
      supplied: "mp3"
      solution: 'html, flash'
    
  fakeEnd: (status) ->
    return unless status.duration > 0 and status.currentTime > 1
    timeleft = status.duration - status.currentTime
    if timeleft < 1 and timeleft > 0
      #log.message @fakeEndScheduled
      if @fakeEndScheduled is false
        @fakeEndScheduled = true
        log.warn "Player: segment is #{timeleft} seconds from ending but we can't handle endings - schedule a fake end just before"      
        
        setTimeout (
          => 
            @nextSegment true
            @fakeEndScheduled = false ),
          (timeleft*1000)-50 
    
  pause: (time) ->
    # Pause playback
    log.message "Player: pause: pause at #{time}"

    if time?
      @playIntentOffset = time
      @el.jPlayer('pause', time)
    else
      #@playIntentOffset = null
      @el.jPlayer('pause')
  
  getStatus: ->
    # Be cautious only read from status
    @el.data('jPlayer').status
  
  # TODO: Remove our own playBackRate attribute and use the one on the jPlayer
  #       If it isn't available, there is no reason to try using it.
  setPlayBackRate: (playBackRate) ->
    if playBackRate?
      @playBackRate = playBackRate
    if @el.data('jPlayer').htmlElement.audio?
      if @el.data('jPlayer').htmlElement.audio.playbackRate?
        @el.data('jPlayer').htmlElement.audio.playbackRate = @playBackRate
        log.message "Player: setPlayBackRate: #{@playBackRate}"
        return
    log.message "Player: setPlayBackRate: unable to set playback rate"
  
  # TODO: Don't set the playback rate here
  isPlayBackRateSurpported: ->
    if @el.data('jPlayer').htmlElement.audio.playbackRate?
      return false if $.jPlayer.platform[platform] for platform in ['iphone', 'ipad', 'iPod', 'android']
      return false if /Windows Phone/i.test(navigator.userAgent)
      return true
    else
      return false
  
  stop: () ->
    if @ready?
      @el.jPlayer('stop')
    
  clear: () ->
    if @ready?
      @el.jPlayer('clearMedia')
      
    
  isIOS: () ->
    if /iPad/i.test(navigator.userAgent) or /iPhone/i.test(navigator.userAgent) or /iPod/i.test(navigator.userAgent)
      return true
    else
      return false
  
      
  updateHtml: (segment) ->
    # Update player rendering for current time of section
    
    if not segment?
      log.error "Player: updateHtml called with no segment"
      return

    if segment.state() isnt 'resolved'
      log.error "Player: updateHtml called with unresolved segment"
      return

    log.group "Player: updateHtml: rendering segment #{segment.url()}, start #{segment.start}, end #{segment.end}", segment
    @renderTranscript segment
    segment.preloadNext()
    # FIXME: Don't call updateLastMark() here - it's not obvious
    @updateLastMark()
  
  # TODO: Factor out this method and replace it by calls to updateHtml
  renderTranscript: (segment) ->
    if segment?
      segment.done (segment) -> LYT.render.textContent segment
    else
      # If there's no media, show nothing
      LYT.render.textContent null
  
  
  whenReady: (callback) ->
    if @ready
      callback()
    else
      @el.bind $.jPlayer.event.ready, callback
  
  # url: url pointing to section or segment
  load: (book, url = null, offset = 0, autoPlay = true) ->
    #return if book.id is @book?.id
    deferred = jQuery.Deferred()
    load = LYT.Book.load book
    
    #LYT.loader.register "Loading book", @book
    
    log.message "Player: Loading book #{book}, segment #{url}, offset: #{offset}, autoPlay #{autoPlay}"
    load.done (book) =>
      @book = book
      jQuery("#book-duration").text @book.totalTime
      @whenReady =>
        if not url? and book.lastmark?
          url    = book.lastmark.URI
          offset = book.lastmark.offset
          log.message "Player: resuming from lastmark #{url}, offset #{offset}"

        failHandler = () =>
          deferred.reject()
          log.error "Player: failed to find segment"

        doneHandler = (segment) =>
          deferred.resolve @book
          @playSegmentOffset segment, offset, autoPlay
          log.message "Player: found segment #{segment.url()} - playing"

        if url?
          promise = @playlist().segmentByURL url
          promise.done doneHandler
          promise.fail =>
            log.error "Player: failed to load url #{url} - rewinding to start"
            offset = 0
            promise = @playlist().rewind()
            promise.done doneHandler
            promise.fail failHandler
        else
          promise = @playlist().rewind()
          promise.done doneHandler
          promise.fail failHandler
        
    deferred.promise()

  playSegment: (segment, autoPlay = true) -> @playSegmentOffset segment, 0, autoPlay
    
  playSegmentOffset: (segment, offset = 0, autoPlay = true) -> 
    throw 'Player: playSegmentOffset called with no segment' unless segment?
    segment.done (segment) =>
      if @currentAudio != segment.audio
        @el.jPlayer "setMedia", {mp3: segment.audio}
        @el.jPlayer "load"
        @currentAudio = segment.audio

      offset = segment.end - 1 if offset > segment.end
      offset = segment.start   if offset < segment.start
      
      log.message "Player: playSegmentOffset: play #{segment.url()}, offset #{offset}"

      if @getStatus()?.paused and not autoPlay
        @el.jPlayer "pause", offset
      else
        @el.jPlayer "play", offset

      $("#player-chapter-title h2").text segment.section.title
      @updateHtml segment

  playSection: (section, offset = 0, autoPlay = true) ->
    section = @playlist().rewind() unless section?
    LYT.loader.register "Loading book", section
    
    section.done (section) =>
      log.message "Player: Playlist current section #{@section().id}"
      # Get the media obj
      @playlist().segmentBySectionOffset section, offset
      @playSegmentOffset @segment(), offset, autoPlay
      
    section.fail ->
      log.error "Player: Failed to load section #{section}"

  nextSegment: (autoPlay = false) ->
    # FIXME: We shouldn't throw an error on a call to nextSegment if the playlist isn't there
    return null unless @playlist()?
    if @playlist().hasNextSegment() is false
      LYT.render.bookEnd()
      return null
    @seekedLoadSegmentLock = true
    segment = @playlist().nextSegment()
    log.message "Player: nextSegment: " + if segment.state() is "resolved" then "#{segment.url()}, start #{segment.start}" else '(pending)'
    @playSegment segment, autoPlay
    segment.always => @seekedLoadSegmentLock = false

  previousSegment: (autoPlay = false) ->
    return null unless @playlist()?.hasPreviousSegment()
    @seekedLoadSegmentLock = true
    segment = @playlist().previousSegment()
    @playSegment segment, autoPlay
    segment.always => @seekedLoadSegmentLock = false
      
  
  updateLastMark: (force = false) ->
    return unless LYT.session.getCredentials() and LYT.session.getCredentials().username isnt LYT.config.service.guestLogin
    return unless @book? and @section()?
    @segment().done (segment) =>
      # FIXME: Rewrite to only use book time
      now = (new Date).getTime()
      interval = LYT.config.player?.lastmarkUpdateInterval or 10000
      return unless force or not @lastBookmark or now - @lastBookmark > interval
      return if @getStatus().currentTime is 0 or @playIntentOffset > @getStatus().currentTime
      @book.setLastmark segment, @getStatus().currentTime
      @lastBookmark = now
  
  getCurrentlyPlaying: ->
    return null unless @book? and @section()?.state() is "resolved"
    book:    @book.id
    section: @section()?.url
    segment: @segment()?.id
    
  getCurrentlyPlayingUrl: (absolute=true, resolution='book') ->
    # Returns the url of the currently playing book
    # Accepts a resolution a string that is either 'book', 'section' or 'offset'
    # Defaults to 'book'
    # If absolute is true it returns the full url with domain
    
    return null unless @book? and @section()?.state() is "resolved"
    
    # FIXME: Don't return urls that only the controllers should know about
    url = "#book-play?book=#{@book.id}"
    if resolution in ['section', 'offset']
      url = url + "&section=#{@section().id}"  
      if resolution is 'offset' and @time?
        url = url + "&offset=#{@time}"
    
    if absolute
      if document.baseURI?
        return document.baseURI + url
      else
        return window.location.hostname+'/'+ url 
    
    return url
