# This module Controller
LYT.control =    
  login: (type, match, ui, page) ->
    $("#login-form").submit (event) ->
      
      $.mobile.showPageLoadingMsg()
      $("#password").blur()
      
      LYT.service.logOn($("#username").val(), $("#password").val())
        .done ->
          $.mobile.changePage "#bookshelf"
        
        .fail ->
          log.message "log on failure"
        
      event.preventDefault()
      event.stopPropagation()
    
  
  bookshelf: (type, match, ui, page) ->
    $.mobile.showPageLoadingMsg()
    
    content = $(page).children(":jqmData(role=content)")
    
    LYT.bookshelf.load()
      .done (books) ->
        LYT.render.bookshelf(books, content)
        
        ###
        $content.find('a').click ->
          alert 'We got some dixie chicks for ya while you wait for your book!'
          if LYT.player.ready
            LYT.player.silentPlay()
          else
            LYT.player.el.bind $.jPlayer.event.ready, (event) ->
              LYT.player.silentPlay()
        ###
        
        $.mobile.hidePageLoadingMsg()
      
      .fail (error, msg) ->
        log.message "failed with error #{error} and msg #{msg}"
  
  
  bookDetails: (type, match, ui, page) ->
    $.mobile.showPageLoadingMsg()
    params = LYT.router.getParams(match[1])
    
    $.mobile.showPageLoadingMsg()
    content = $(page).children( ":jqmData(role=content)" )
    
    # TODO: validate query string
    
    LYT.Book.load(params.book)
      .done (book) ->
        log.message book
        
        LYT.render.bookDetails(book, content)
        
        content.find("#play-button").click (e) =>
          e.preventDefault()
          $.mobile.changePage("#book-play?book=" + book.id)
        
        #LYT.render.covercacheOne content.find("figure"), bookId
        
        #$page.page()
        $.mobile.hidePageLoadingMsg()
        #$.mobile.changePage page, options
      
      .fail (error, msg) ->
        log.message "failed with error #{error} and msg #{msg}"
  
  bookIndex: (type, match, ui, page) ->
    params = LYT.router.getParams(match[1])
    content = $(page).children( ":jqmData(role=content)" )
    
    if params.book
      $.mobile.showPageLoadingMsg()
      LYT.Book.load(params.book)
        .done (book) ->
          
          LYT.render.bookIndex(book, content)
          $.mobile.hidePageLoadingMsg()
          
          #jQuery("#book-index ol l").each ->
          #  #log.message jQuery(@).attr('href')
          #  #attr = jQuery(@).attr('href') + '?book=15000'
          #  #jQuery(@).attr('href', attr)
  
  bookPlayer: (type, match, ui, page) ->
    $.mobile.showPageLoadingMsg()
    
    params = LYT.router.getParams(match[1])
    
    #fixme: next line should probably update the href preserving current parameters in hash instead of replacing
    header = $(page).children( ":jqmData(role=header)")
    $('#book-index-button').attr 'href', """#book-index?book=#{params.book}"""
    
    section = params.section or 0
    offset = params.offset or 0
    
    LYT.Book.load(params.book)
      .done (book) ->
        
        LYT.render.bookPlayer book, $(page)
        
        LYT.player.load book, section, offset
        
        ###
        $("#book-play").bind "swiperight", ->
            LYT.player.nextSection()
        
        $("#book-play").bind "swipeleft", ->
            LYT.player.previousSection()
        ###
        
        $.mobile.hidePageLoadingMsg()
        
      .fail () ->
        log.error "Control: Failed to load book ID #{params.book}"
  
  search: (type, match, ui, page) ->
    if match?[1]
      params = LYT.router.getParams match[1]
    else
      params = {}
    
    params.term = jQuery.trim(decodeURI(params.term or "")) or null
    
    content = $(page).children( ":jqmData(role=content)" )
    
    LYT.search.attachAutocomplete $('#searchterm')
    # TODO: Shouldn't this only be bound once? Or does jQuery take care of that?
    $(LYT.search).bind 'autocomplete', (event) ->
      log.message "Autocomplete suggestions: #{event.results}"
    
    loadResults = (term, page = 1) ->
      LYT.search.full(term, page)
        .done (results) ->
          $("#more-search-results").unbind "click"
          $("#more-search-results").click (event) ->
            loadResults results.nextPage if results.nextPage
            event.preventDefault()
            event.stopImmediatePropagation()
          
          LYT.render.searchResults(results, content)
          $.mobile.hidePageLoadingMsg()
    
    # this allows for bookmarkable search terms
    if params.term and $('#searchterm').val() isnt params.term
      $('#searchterm').val params.term
      loadResults params.term
      ###
      LYT.search.full(params.term)
        .done (results) ->
          $("#more-search-results").unbind "click"
          $("#more-search-results").click -> (event)
            
            event.preventDefault()
            event.stopImmediatePropagation()
          
          LYT.render.searchResults(results, content)
          $.mobile.hidePageLoadingMsg()
      ###
    
    $("#search-form").submit (event) ->
      log.message 'you searched'      
      $('#searchterm').blur()
      $.mobile.showPageLoadingMsg()
      
      term = encodeURI $('#searchterm').val()
      loadResults $('#searchterm').val()
      $.mobile.changePage "#search?term=#{term}" , transition: "none"
      
      event.preventDefault()
      event.stopImmediatePropagation()
      
      #$.mobile.changePage "#search",
      #  allowSamePageTransition: true
      #  type: "get"
      #  data: $("form#search-form").serialize()
      
      #$.mobile.changePage("#{page}?term=#{$('#searchterm').val()}")
      
      #LYT.search.full()
      #  .done (results) ->
      #    LYT.render.searchResults(results, content)
      #    $.mobile.hidePageLoadingMsg()
      
  
  
  settings: (type, match, ui, page) ->
    style = LYT.settings.get('textStyle')
    
    $("#style-settings").find("input").each ->
      name = $(this).attr 'name'
      val = $(this).val()
      
      switch name
        when 'font-size', 'font-family'
          if val is style[name]
            $(this).attr("checked", true).checkboxradio("refresh");
        when 'marking-color'
          colors = val.split(';')
          if style['background-color'] is colors[0] and style['color'] is colors[1]
            $(this).attr("checked", true).checkboxradio("refresh");
            
    $("#style-settings input").change (event) ->
      target = $(event.target)
      name = target.attr 'name'
      val = target.val()
      
      switch name
        when 'font-size', 'font-family'
          style[name] = val
        when 'marking-color'
          colors = val.split(';')
          style['background-color'] = colors[0]
          style['color'] = colors[1]
      
      LYT.settings.set('textStyle', style)
      LYT.render.setStyle()
  
  profile: (type, match, ui, page) ->
    $("#log-off").click (event) ->
      LYT.service.logOff()
    
  
