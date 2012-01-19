# Requires `/common`  

# -------------------

# This file contains the `LYT.DTBDocument` class, which forms the basis for other classes.
# It is not meant for direct instantiation.

# FIXME: Improve error-handling, and send requests through service (or something)

do ->
  # Meta-element name attribute values to look for
  # Name attribute values for nodes that may appear 0-1 times per file  
  # Names that may have variations (e.g. `ncc:format` is the deprecated form of `dc:format`) are defined a arrays.
  # C.f. [The DAISY 2.02 specification](http://www.daisy.org/z3986/specifications/daisy_202.html#h3metadef)
  # TODO: Comment out the things we'll never need to speed up the processing
  METADATA_NAMES =
    singular:
      coverage:         "dc:coverage"
      date:             "dc:date"
      description:      "dc:description"
      format:          ["dc:format", "ncc:format"]
      identifier:      ["dc:identifier", "ncc:identifier"]
      publisher:        "dc:publisher"
      relation:         "dc:relation"
      rights:           "dc:rights"
      source:           "dc:source"
      subject:          "dc:subject"
      title:            "dc:title"
      type:             "dc:type"
      charset:          "ncc:charset"
      depth:            "ncc:depth"
      files:            "ncc:files"
      footnotes:        "ncc:footnotes"
      generator:        "ncc:generator"
      kByteSize:        "ncc:kByteSize"
      maxPageNormal:    "ncc:maxPageNormal"
      multimediaType:   "ncc:multimediaType"
      pageFront:       ["ncc:pageFront", "ncc:page-front"]
      pageNormal:      ["ncc:pageNormal", "ncc:page-normal"]
      pageSpecial:     ["ncc:pageSpecial", "ncc:page-special"]
      prodNotes:        "ncc:prodNotes"
      producer:         "ncc:producer"
      producedDate:     "ncc:producedDate"
      revision:         "ncc:revision"
      revisionDate:     "ncc:revisionDate"
      setInfo:         ["ncc:setInfo", "ncc:setinfo"]
      sidebars:         "ncc:sidebars"
      sourceDate:       "ncc:sourceDate"
      sourceEdition:    "ncc:sourceEdition"
      sourcePublisher:  "ncc:sourcePublisher"
      sourceRights:     "ncc:sourceRights"
      sourceTitle:      "ncc:sourceTitle"
      timeInThisSmil:  ["ncc:timeInThisSmil", "time-in-this-smil"]
      tocItems:        ["ncc:tocItems", "ncc:tocitems", "ncc:TOCitems"]
      totalElapsedTime:["ncc:totalElapsedTime", "total-elapsed-time"]
      totalTime:       ["ncc:totalTime", "ncc:totaltime"]
    
    # Name attribute values for nodes that may appear multiple times per file
    plural:
      contributor: "dc:contributor"
      creator:     "dc:creator"
      language:    "dc:language"
      narrator:    "ncc:narrator"
  
  # -------
  
  createHTMLDocument = do ->
    if typeof document.implementation?.createHTMLDocument is "function"
      return -> document.implementation.createHTMLDocument ""
    
    # Firefox does not support `document.implementation.createHTMLDocument()`  
    # The following work-around is adapted from [this gist](http://gist.github.com/49453)
    if XSLTProcessor?
      return ->
        processor = new XSLTProcessor();
        template = [
          """<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">"""
          """<xsl:output method="html"/>"""
          """<xsl:template match="/">"""
          """<html><head><title>HTML Document</title></head><body/></html>"""
          """</xsl:template>"""
          """</xsl:stylesheet>"""
        ].join("")
        doc = document.implementation.createDocument "", "foo", null
        range = doc.createRange()
        range.selectNodeContents doc.documentElement
        
        try
          doc.documentElement.appendChild range.createContextualFragment(template)
        catch error
          return null
        
        processor.importStylesheet doc.documentElement.firstChild
        html = processor.transformToDocument doc
        return null unless html.body
        html
    
    else if typeof document.implementation?.createDocumentType is "function"
      doctype = document.implementation.createDocumentType "HTML", "-//W3C//DTD HTML 4.01//EN", "http://www.w3.org/TR/html4/strict.dtd"
      return ->
        document.implementation.createDocument "", "HTML", doctype
    
    else
      null
  
  # -------
  
  # This class serves as the parent of the `SMILDocument` and `TextContentDocument` classes.  
  # It is not meant for direct instantiation - instantiate the specific subclasses.
  class LYT.DTBDocument
    
    # The constructor takes 1-2 arguments (the 2nd argument is optional):  
    # - url: (string) the URL to retrieve
    # - callback: (function) called when the download is complete (used by subclasses)
    #
    # `LYT.DTBDocument` acts as a Deferred.
    constructor: (@url, callback = null) ->
      # The instance will act as a Deferred
      deferred = jQuery.Deferred()
      deferred.promise this
      
      # This instance property will hold the XML/HTML
      # document, once it's been downloaded
      @source = null
      
      # Set up some local variables
      dataType = if (/\.x?html?$/i).test @url then "html" else "xml"
      attempts = LYT.config.dtbDocument?.attempts or 3
      useForceClose = yes unless LYT.config.dtbDocument?.useForceClose? is no
      
      # Internal function to convert raw text to a HTML DOM document
      coerceToHTML = (responseText) =>
        return null unless createHTMLDocument?
        
        log.message "DTB: Coercing #{@url} into HTML"
        # Grab everything inside the "root" `<html></html>` element
        try
          markup = responseText.match /<html[^>]*>([\s\S]+)<\/html>\s*$/i
        catch e
          #log.error "DTB: Failed to coerce markup into HTML"
          markup = ["", responseText]
        
        # Give up, if nothing was found
        return null unless (markup = markup[1])?
        
        # Create the DOM document
        html = createHTMLDocument()
        
        # Give up if nothing was created
        return null unless html?
        
        # Insert the markup into the document
        html.documentElement.innerHTML = markup
        
        # Wrap it with jQuery and return it
        jQuery html
      
      
      # This function will be called, when a DTB document has been successfully downloaded
      loaded = (document, status, jqXHR) =>
        # TODO: Now that all the documents _should be_ valid XHTML, they should be parsable
        # as XML. I.e. `coerceToHTML` shouldn't be necessary _unless_ there's a `parsererror`.
        # But for some reason, that causes a problem elsewhere in the system, so right now
        # _all_ html-type documents are forcibly sent through `coerceToHTML` even though
        # it shouldn't be necessary...
        if dataType is "html" or jQuery(document).find("parsererror").length isnt 0
          @source = coerceToHTML jqXHR.responseText
        else
          @source = jQuery document
        resolve()
      
      
      # This function will be called if `load()` (below) fails
      failed = (jqXHR, status, error) =>
        if status is "parsererror"
          log.error "DTB: Parser error in XML response. Attempting recovering"
          @source = coerceToHTML jqXHR.responseText
          resolve()
          return
        
        # If access was denied, try silently logging in and then try again
        if jqXHR.status is 403 and attempts > 0
          log.warn "DTB: Access forbidden - refreshing session"
          LYT.service.refreshSession()
            .done load
            .fail ->
              log.errorGroup "DTB: Failed to get #{@url} (status: #{status})", jqXHR, status, error
              deferred.reject status, error
          return
        
        # If the failure was due to something else (and wasn't an explicit abort)
        # try again, if there are any attempts left
        if status isnt "abort" and attempts > 0
          log.warn "DTB: Unexpected failure (#{attempts} attempts left)"
          load()
          return
        
        # If all else fails, give up
        log.errorGroup "DTB: Failed to get #{@url} (status: #{status})", jqXHR, status, error
        deferred.reject status, error
      
      # Resolve the promise
      resolve = =>
        if @source?
          log.group "DTB: Got: #{@url}", @source
          callback? deferred
          deferred.resolve this
        else
          deferred.reject -1, "FAILED_TO_LOAD"
      
      # Perform the actual AJAX request to load the file
      load = =>
        --attempts
        url = @url
        if useForceClose
          forceCloseMsg = "[forceclose ON]"
          # TODO: Hack'y way of appending the `forceclose` parameter... ugh
          if /\?.+$/.test url
            url = "#{url}&forceclose=true"
          else
            url = "#{url}?forceclose=true"
        else
          forceCloseMsg = ""
          
        log.message "DTB: Getting: #{@url} (#{attempts} attempts left) #{forceCloseMsg}"
        request = jQuery.ajax {
          url:      url
          dataType: dataType # TODO: It should be fine to just put "xml" here... but it ain't
          async:    yes
          cache:    yes
          success:  loaded
          error:    failed
          timeout:  20000
        }
      
      load()
      deferred
    
    
    # Parse and return the metadata as an array
    getMetadata: ->
      return {} unless @source?
      
      # Return cached metadata, if available
      return @_metadata if @_metadata?
      
      # Find the `meta` elements matching the given name-attribute values.
      # Multiple values are given as an array
      findNodes = (values) =>
        values = [values] unless values instanceof Array
        nodes  = []
        selectors = ("meta[name='#{value}']" for value in values).join(", ")
        @source.find(selectors).each ->
          node = jQuery this
          nodes.push {
            content: node.attr("content")
            scheme:  node.attr("scheme") or null
          }
        
        return null if nodes.length is 0
        return nodes
      
      xml = @source.find("head").first()
      @_metadata = {}
      
      for own name, values of METADATA_NAMES.singular
        found = findNodes values
        @_metadata[name] = found.shift() if found?
      
      for own name, values of METADATA_NAMES.plural
        found = findNodes values
        @_metadata[name] = found if found?
      
      @_metadata
    
  