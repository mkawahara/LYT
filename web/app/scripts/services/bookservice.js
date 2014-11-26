'use strict';

angular.module('lyt3App')
  .factory('BookService', [ '$q', '$rootScope', '$location', '$interval', '$log', 'LYTConfig', 'Book', 'BookNetwork', 'NativeGlue',
  function( $q, $rootScope, $location, $interval, $log,  LYTConfig, Book, BookNetwork, NativeGlue ) {
    var currentBook;

    var getCurrentPOsition = function( ) {
      if ( !currentBook ) {
        return;
      }

      var bookData = NativeGlue.getBooks( ).filter( function( bookData ) {
        return bookData.id === currentBook.id;
      } ).pop();

      if ( bookData ) {
        currentBook.currentPosition = bookData.offset;
      }

      return currentBook.currentPosition;
    };

    $interval( function( ) {
      if ( currentBook ) {
        currentBook.setLastmark( );
      }
    }, LYTConfig.player.lastmarkUpdateInterval || 10000 );

    // Public API here
    var BookService = {
      get currentBook( ) {
        return currentBook;
      },

      set currentBook( book ) {
        currentBook = book;
        $log.info( 'BookService: set currentBook:', book.id );

        NativeGlue.setBook( book.structure );
      },

      play: function( bookId, offset ) {
        $log.info( 'BookService: play:', bookId, offset );
        if ( !bookId ) {
          if ( !currentBook ) {
            return;
          }

          if ( offset === undefined ) {
            offset = getCurrentPOsition( );
          }

          NativeGlue.play( currentBook.id, offset );
          BookService.playing = true;
        } else if ( currentBook && currentBook.id === bookId ) {
          if ( offset === undefined ) {
            offset = getCurrentPOsition( );
          }

          NativeGlue.play( bookId, offset );
          BookService.playing = true;
        } else {
          BookService.loadBook( bookId )
            .then( function( book ) {
              BookService.currentBook( book );

              if ( offset === undefined ) {
                offset = getCurrentPOsition( );
              }

              NativeGlue.play( bookId, offset );
              BookService.playing = true;
            } );
        }
      },

      skip: function( diff ) {
        if ( currentBook ) {
          $log.info( 'BookService: ship:', currentBook.id, diff, currentBook.currentPosition + diff );
          BookService.play( currentBook.id, currentBook.currentPosition + diff );
        }
      },

      stop: function( ) {
        $log.info( 'BookService: stop' );
        NativeGlue.stop( );
      },

      loadBook: function( bookId ) {
        var deferred = $q.defer();

        if ( currentBook && currentBook.id === bookId ) {
          $log.info( 'BookService: loadBook, already loaded', bookId );
          deferred.resolve( currentBook );
          return deferred.promise;
        }

        $log.info( 'BookService: loadBook', bookId );

        BookNetwork
          .withLogOn( function( ) {
            return Book.load( bookId );
          } )
            .then( function( book ) {
              deferred.resolve( book );
              BookService.currentBook = book;

              NativeGlue.setBook( book.structure );

              NativeGlue.getBooks( )
                .some( function( bookData ) {
                  if ( bookData.id === book.id ) {
                    book.currentPosition = Math.max( bookData.offset || 0, book.currentPosition || 0, 0 );
                    return true;
                  }
                } );
            } )
            .catch( function( ) {
              deferred.reject( );
            } );

        return deferred.promise;
      },

      playing: false
    };

    $rootScope.$on( 'play-time-update', function( $currentScope, bookId, offset ) {
      if ( !currentBook || currentBook.id !== bookId ) {
        if ( $location.path( ).indexOf( 'book-player' ) > -1 ) {
          var bookPath = '/book-player/' + bookId;
          $location.path( bookPath );
        } else {
          BookService.loadBook( bookId )
            .then( function( book ) {
              book.currentPosition = offset;
              BookService.playing = true;
            } );
        }
      } else {
        currentBook.currentPosition = offset;
        BookService.playing = true;
      }
    } );

    $rootScope.$on( 'play-stop', function( $currentScope, bookId ) {
      if ( currentBook && currentBook.id === bookId ) {
        BookService.playing = false;
      }
    } );

    $rootScope.$on( 'play-end', function( $currentScope, bookId ) {
      if ( currentBook && currentBook.id === bookId ) {
        BookService.playing = false;
        currentBook.currentPosition = currentBook.duration;
      }
    } );

    return BookService;
  }] );
