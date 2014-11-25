'use strict';

/**
 * @ngdoc service
 * @name lyt3App.DODP
 * @description
 * # DODP
 * Factory in the lyt3App.
 */
angular.module( 'lyt3App' )
  .factory( 'DODP', [ '$sanitize', '$http', '$q', 'xmlParser', 'DODPErrorCodes',
  function( $sanitize, $http, $q, xmlParser, DODPErrorCodes ) {
    /*jshint quotmark: false */
    // jscs:disable validateQuoteMarks
    var soapTemplate = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
      "<SOAP-ENV:Envelope\n" +
      " xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\"\n" +
      " xmlns:ns1=\"http://www.daisy.org/ns/daisy-online/\"\n" +
      " xmlns:ns2=\"http://www.daisy.org/z3986/2005/bookmark/\">\n" +
      "<SOAP-ENV:Body>SOAPBODY</SOAP-ENV:Body>\n" +
      "</SOAP-ENV:Envelope>";
    // jscs:enable validateQuoteMarks
    /*jshint quotmark: single */


    var appendToXML = function( xml, nodeName, data ) {
      var nsid = 'ns1:';
      if ( nodeName.indexOf( ':' ) > -1 ) {
        nsid = '';
      }

      xml += '<' + nsid + nodeName + '>' + toXML( data ) + '</' + nsid +
        nodeName + '>';

      return xml;
    };

    var toXML = function( hash ) {
      var xml = '';
      // Handling of namespaces could be done here by initializing a string
      // containing the necessary declarations that can be inserted in append()

      // Append XML-strings by recursively calling `toXML`
      // on the data

      var type = typeof hash;
      if ( [ 'string', 'number', 'boolean' ].indexOf( type ) > -1 ) {
        // If the argument is a string, number or boolean,
        // then coerce it to a string and use a pseudo element
        // to handle the escaping of special chars
        xml = $sanitize( hash );
      } else if ( type === 'object' && type !== null ) {
        // If the argument is an object, go through its members
        Object.keys( hash ).forEach( function( key ) {
          var value = hash[ key ];
          if ( value instanceof Array ) {
            value.forEach( function( item ) {
              xml = appendToXML( xml, key, item );
            } );
          } else {
            xml = appendToXML( xml, key, value );
          }
        } );
      }

      return xml;
    };

    var createRequest = function( action, data ) {
      var requestData = {};
      requestData[ action ] = data || {};

      var xmlBody = soapTemplate.replace( /SOAPBODY/, toXML( requestData ) );

      var defer = $q.defer( );

      // var url = document.location.protocol + '//' + document.location.host + '/DodpMobile/Service.svc';
      var url = '/DodpMobile/Service.svc';

      $http( {
        url: url,
        method: 'POST',
        headers: {
          soapaction: '/' + action,
          'Content-Type': 'text/xml; charset=UTF-8'
        },
        data: xmlBody,
        transformResponse: function( data ) {
          return xmlStr2Json( data );
        }
      } ).success( function( response ) {
        var Body = response.Body;
        if ( Body.Fault ) {
          defer.reject( [ DODPErrorCodes.identifyDODPError( Body.Fault.faultcode ), Body.Fault.faultstring ] );
        } else {
          defer.resolve( response );
        }
      } ).catch( function( response ) {
        defer.reject( response );
      } );

      return defer.promise;
    };

    var xml2Json = function( xmlDom, json ) {
      var tagName = xmlDom.nodeName.replace( /^s:/, '' );
      var attrs;
      var item;
      if ( xmlDom.attributes ) {
        attrs = Array.prototype.reduce.call( xmlDom.attributes, function(
          attrs, attr ) {
          var name = attr.name;
          var idx = name.indexOf( ':' );
          var ignore = false;
          if ( idx > -1 ) {
            var ns = name.substr( 0, idx );
            if ( [ 'xml', 'xmlns', 'ns1', 'ns2' ].indexOf( ns ) > -1 ) {
              ignore = true;
            }
          }

          if ( [ 'xmlns', 'dir' ].indexOf( name ) > -1 ) {
            ignore = true;
          }

          var value;
          try {
            value = JSON.parse( attr.value );
          } catch ( exp ) {
            value = attr.value;
          }

          if ( !ignore ) {
            attrs[ name ] = value;
          }

          return attrs;
        }, {} );

        if ( Object.keys( attrs ).length === 0 ) {
          attrs = undefined;
        }
      }

      var children = xmlDom.children || xmlDom.childNodes;
      if ( children && children.length === 1 && children[ 0 ].nodeName === '#text' ) {
        xmlDom = children[ 0 ];
        children = null;
      }

      if ( children && children.length > 0 ) {
        item = {};

        if ( attrs ) {
          item.attrs = attrs;
        }

        Array.prototype.forEach.call( xmlDom.childNodes, function( el ) {
          xml2Json( el, item );
        } );
      } else {
        var textContent = xmlDom.textContent;
        var value;
        try {
          value = JSON.parse( textContent );
        } catch ( exp ) {
          value = textContent;
        }

        item = value;

        if ( attrs ) {
          item = {
            attrs: attrs,
            value: value
          };
        }
      }

      if ( json[ tagName ] ) {
        if ( json[ tagName ] instanceof Array ) {
          json[ tagName ].push( item );
        } else {
          json[ tagName ] = [ json[ tagName ], item ];
        }
      } else {
        json[ tagName ] = item;
      }
    };

    var xmlStr2Json = function( xmlStr ) {
      var xmlDOM = xmlParser.parse( xmlStr );
      var json = {};

      if ( xmlDOM.childNodes ) {
        Array.prototype.forEach.call( xmlDOM.childNodes[ 0 ].childNodes,
          function( domEl ) {
            xml2Json( domEl, json );
          } );
      }

      return angular.extend( {
        Body: {},
        Header: {}
      }, json );
    };

    // Convert from floating point in seconds to Dodp offset
    var formatDodpOffset = function( timeOffset ) {
      // TODO: The server doesn't support npt format, though it is required
      // timeOffset: "npt=#{hours}:#{minutes}:#{seconds}"

      var offset = timeOffset;
      var hours = Math.floor( offset / 3600 );
      var minutes = Math.floor(( offset - hours * 3600 ) / 60);
      var seconds = offset - hours * 3600 - minutes * 60;
      if ( hours < 10 ) {
        hours = '0' + hours.toString( );
      }

      if ( minutes < 10 ) {
        minutes = '0' + minutes.toString( );
      }

      if ( seconds < 10 ) {
        seconds = '0' + seconds.toFixed( 2 );
      } else {
        seconds = seconds.toFixed( 2 );
      }

      return '' + hours + ':' + minutes + ':' + seconds;
    };

    var bookmarkToPlainObject = function( bookmark ) {
      return {
        URI: bookmark.URI,
        timeOffset: formatDodpOffset(bookmark.timeOffset),
        note: bookmark.note
      };
    };

    var setnamespace = function(ns, obj) {
      var key, newObj, value;
      if (typeof obj === 'object') {
        if (obj instanceof Array) {
          return obj.map( function( value ) {
            return setnamespace(ns, value);
          } );
        } else {
          newObj = {};
          for (key in obj) {
            value = obj[key];
            newObj[ns + ':' + key] = setnamespace(ns, value);
          }
          return newObj;
        }
      } else {
        return obj;
      }
    };

    // Public API here
    return {
      logOn: function( username, password ) {
        var defer = $q.defer( );

        createRequest( 'logOn', {
          username: username,
          password: password
        } ).then( function( data ) {
          if ( data.Body.logOnResponse && data.Body.logOnResponse.logOnResult ) {
            defer.resolve( data.Header );
          } else {
            defer.reject( data );
          }
        }, function( ) {
          defer.reject( arguments );
        } );

        return defer.promise;
      },
      logOff: function( ) {
        var defer = $q.defer( );
        createRequest( 'logOff' )
          .then( function( data ) {
            if ( data.Body.logOffResponse && data.Body.logOffResponse.logOffResult ) {
              defer.resolve( data.Header );
            } else {
              defer.reject( 'logOffFailed' );
            }
          }, function( ) {
            defer.reject( 'logOffFailed' );
          } );

        return defer.promise;
      },
      getServiceAttributes: function( ) {
        var defer = $q.defer( );
        createRequest( 'getServiceAttributes' )
          .then( function( data ) {
            var getServiceAttributesResponse = data.Body.getServiceAttributesResponse || {};
            var services = getServiceAttributesResponse.serviceAttributes;

            if ( services && Object.keys( services ).length ) {
              defer.resolve( services );
            } else {
              defer.reject(
                'getServiceAttributes failed, missing data.Body.getServiceAttributesResponse.serviceAttributes'
              );
            }
          }, function( ) {
            defer.reject( arguments );
          } );

        return defer.promise;
      },
      setReadingSystemAttributes: function( readingSystemAttributes ) {
        var defer = $q.defer( );
        /* NOTE: input should be:
         */
        readingSystemAttributes = angular.extend( {
          manufacturer: 'NOTA',
          model: 'LYT',
          serialNumber: 1,
          version: 1,
          config: ''
        }, readingSystemAttributes );

        createRequest( 'setReadingSystemAttributes', {
            readingSystemAttributes: readingSystemAttributes
          } )
          .then( function( data ) {
            if ( data.Body.setReadingSystemAttributesResponse.setReadingSystemAttributesResult ) {
              defer.resolve( );
            } else {
              defer.reject( 'setReadingSystemAttributes failed' );
            }
          }, function( ) {
            defer.reject( 'setReadingSystemAttributes failed' );
          } );

        return defer.promise;
      },
      getServiceAnnouncements: function( ) {
        var defer = $q.defer( );
        createRequest( 'getServiceAnnouncements' )
          .then( function( data ) {
            var body = data.Body;
            var announcements = ( ( body.getServiceAnnouncementsResponse || {} )
              .announcements || {} ).announcement || [ ];
            defer.resolve( announcements );
          }, function( ) {
            defer.reject( 'getServiceAnnouncements failed' );
          } );

        return defer.promise;
      },
      markAnnouncementsAsRead: function( ) {
        var defer = $q.defer( );
        defer.reject( );

        return defer.promise;
      },
      getContentList: function( listIdentifier, firstItem, lastItem ) {
        var defer = $q.defer( );
        createRequest( 'getContentList', {
            id: listIdentifier,
            firstItem: firstItem,
            lastItem: lastItem
          } )
          .then( function( data ) {
            var Body = data.Body || {};
            var getContentListResponse = Body.getContentListResponse || {};
            var contentList = getContentListResponse.contentList || {};
            if ( contentList ) {
              var list = {
                id: listIdentifier,
                items: [ ]
              };

              if ( !contentList.contentItem ) {
                return defer.resolve( list );
              }

              var attrs = contentList.attrs || {};
              list.id = attrs.id || listIdentifier;
              list.firstItem = attrs.firstItem;
              list.lastItem = attrs.lastItem;
              list.totalItems = attrs.totalItems;

              var contentItem = contentList.contentItem || [ ];
              if ( !( contentItem instanceof Array ) ) {
                contentItem = [ contentItem ];
              }

              list.items = contentItem.map(
                function( item ) {
                  // TODO: Using $ as a make-shift delimiter in XML? Instead of y'know using... more XML? Wow.
                  // To quote [Nokogiri](http://nokogiri.org/): "XML is like violence - if it doesn’t solve your problems, you are not using enough of it."
                  // See issue #17 on Github

                  var label = item.label.text || '';
                  var labelArr = label.split( '$' );
                  return {
                    id: item.attrs.id,
                    author: labelArr[ 0 ],
                    title: labelArr[ 1 ]
                  };
                } );

              defer.resolve( list );
            } else {
              defer.reject( 'getContentList failed' );
            }
          }, function( ) {
            defer.reject( 'getContentList failed' );
          } );

        return defer.promise;
      },
      issueContent: function( contentID ) {
        var defer = $q.defer( );

        createRequest( 'issueContent', {
            contentID: contentID
          } )
          .then( function( data ) {
            var Body = data.Body;
            if ( Body.issueContentResponse.issueContentResult ) {
              defer.resolve( );
            } else {
              defer.reject( 'issueContent failed 2' );
            }
          }, function( rejected ) {
            defer.reject( rejected );
          } );

        return defer.promise;
      },
      returnContent: function( ) {
        var defer = $q.defer( );
        defer.reject( );

        return defer.promise;
      },
      getContentMetadata: function( ) {
        var defer = $q.defer( );
        defer.reject( );

        return defer.promise;
      },
      getContentResources: function( contentID ) {
        var defer = $q.defer( );

        createRequest( 'getContentResources', {
            contentID: contentID
          } )
          .then( function( data ) {
            var Body = data.Body;
            var resources = Body.getContentResourcesResponse.resources.resource
              .reduce( function( resources, item ) {
                resources[ item.attrs.localURI ] = item.attrs.uri;
                return resources;
              }, {} );

            defer.resolve( resources );
          }, function( ) {
            defer.reject( 'getContentResources failed' );
          } );

        return defer.promise;
      },
      getBookmarks: ( function( ) {
        /**
         * Convert from Dodp offset to floating point in seconds
         * TODO: Implement correct parsing of all time formats provided in
         *       http://www.daisy.org/z3986/2005/Z3986-2005.html#Clock
         * Parse offset strings ("HH:MM:SS.ss") to seconds, e. g.
         *     parseOffset("1:02:03.05") #=> 3723.05
         * We keep this function as well as parseTime in LYTUtils because they
         * are used to parse formats that are not completely identical.
         */

        var parseOffset = function( timeOffset ) {
          var values = timeOffset.match( /\d+/g );
          if ( values && values.length === 4 ) {
            values[ 3 ] = values[ 3 ] || '0';
            values = values.map( function( val ) {
              return parseFloat( val, 10 );
            } );

            return values[ 0 ] * 3600 + values[ 1 ] * 60 + values[ 2 ] +
              values[ 3 ];
          }
        };

        var deserialize = function( data ) {
          if ( !data ) {
            return;
          }

          var uri = data.URI;

          var timeOffset = parseOffset( data.timeOffset );
          var note = ( data.note || {} ).text || '-';
          if ( uri && timeOffset !== undefined ) {
            return {
              ncxRef: null,
              URI: uri,
              timeOffset: timeOffset,
              note: {
                text: note
              }
            };
          }
        };

        return function( contentID ) {
          var defer = $q.defer( );

          createRequest( 'getBookmarks', {
              contentID: contentID
            } )
            .then( function( data ) {
              var Body = data.Body;
              var getBookmarksResponse = Body.getBookmarksResponse || {};
              var bookmarkSet = getBookmarksResponse.bookmarkSet || {};
              var title = bookmarkSet.title;
              var bookmarks = bookmarkSet.bookmark || [ ];
              if ( bookmarks ) {
                if ( !( bookmarks instanceof Array ) ) {
                  bookmarks = [ bookmarks ];
                }
              }

              var res = {
                bookmarks: bookmarks.map( deserialize ).filter(
                  function( bookmark ) {
                    return !!bookmark;
                  } ),
                book: {
                  uid: bookmarkSet.uid,
                  title: {
                    text: title.text,
                    audio: title.audio
                  }
                },
                lastmark: deserialize( bookmarkSet.lastmark )
              };

              defer.resolve( res );
            }, function( ) {
              defer.reject( 'getBookmarks failed' );
            } );

          return defer.promise;
        };
      } )( ),
      setBookmarks: function( book ) {
        var defer = $q.defer( );

        if ( !book || !book.id ) {
          defer.reject( 'setBookmarks failed - you have to provide a book with an id' );
          return;
        }

        var data = {
          contentID: book.id
        };

        var uid = book.getMetadata().identifier ? book.getMetadata().identifier.content : void 0;

        var bookmarkSet = {
          title: book.title,
          uid: uid,
          bookmark: book.bookmarks.map( bookmarkToPlainObject ),
        };

        if ( book.lastmark ) {
          bookmarkSet.lastmark = bookmarkToPlainObject( book.lastmark );
        }

        bookmarkSet = setnamespace( 'ns2', bookmarkSet );
        data[ 'ns2:bookmarkSet' ] = bookmarkSet;

        createRequest( 'setBookmarks', data )
          .then( function( data ) {
            var setBookmarksResponse = data.Body.setBookmarksResponse || {};
            defer.resolve( !!setBookmarksResponse.setBookmarksResult );
          }, function( rejected ) {
            defer.reject( rejected );
          } );

        return defer.promise;
      },
    };
  } ] );
