package dk.nota.lyt.player;

import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.math.BigDecimal;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioManager;
import android.media.AudioManager.OnAudioFocusChangeListener;
import android.media.MediaPlayer.OnCompletionListener;
import android.net.ConnectivityManager;
import android.util.Log;
import dk.nota.lyt.Book;
import dk.nota.lyt.BookInfo;
import dk.nota.lyt.Section;
import dk.nota.lyt.SoundBite;
import dk.nota.lyt.SoundFragment;
import dk.nota.lyt.player.lock.LockScreenManager;
import dk.nota.lyt.player.task.AbstractTask;
import dk.nota.lyt.player.task.GetBookTask;
import dk.nota.lyt.player.task.StreamBiteTask;
import dk.nota.utils.MediaPlayer;
import dk.nota.utils.WorkerThread;

public class BookPlayer implements DownloadThread.Callback, OnCompletionListener, OnAudioFocusChangeListener {
	
	interface EventListener {
		void onEvent(Event event, Object...params);
	}

	private static BigDecimal THOUSAND = new BigDecimal(1000);

	private NextPlayerThread mNextPlayerThread;
	private StreamingThread mStreamingThread;
	private DownloadThread mDownloaderThread;
	private ProgressThread mProgressThread;
	private MediaPlayer mCurrentPlayer;
	private MediaPlayer mNextPlayer;
	
	private BroadcastReceiver mNetworkStateReceiver;
	private NotificationManager mNotificationManager = new NotificationManager();

	private Book mBook;
	private BigDecimal mCurrentEnd;
	private EventListener mEventListener;
	
	private LockScreenManager mLockScreenManager;
	private AudioManager mAudioManager;


	private boolean mOnline;

	BookPlayer() {
		mNextPlayerThread = new NextPlayerThread();
		mNextPlayerThread.start();
		mStreamingThread = new StreamingThread();
		mStreamingThread.start();
		mDownloaderThread = new DownloadThread(this);
		mDownloaderThread.start();
		mProgressThread = new ProgressThread();
		mProgressThread.start();
		
		listenToConnectivity();	
		mAudioManager = (AudioManager) PlayerApplication.getInstance().getSystemService(Context.AUDIO_SERVICE);
		mLockScreenManager = new LockScreenManager();
	}
	
	void onDestroy() {
		unlistenToConnectivity();
		mNextPlayerThread.shutdown();
		mStreamingThread.shutdown();
		mDownloaderThread.shutdown();
		stop();
	}
	
	void setEventListener(EventListener listener) {
		this.mEventListener = listener;
	}

	public void setBook(String bookJSON) {
		PlayerApplication.getInstance().getBookService().setBook(bookJSON);
	}
	
	public void clearBook(String bookId) {
		PlayerApplication.getInstance().getBookService().clearBook(bookId);
	}
	
	public void clearBookCache(String bookId) {
		PlayerApplication.getInstance().getBookService().clearBookCache(bookId);
	}
	
	public BookInfo[] getBooks() {
		return PlayerApplication.getInstance().getBookService().getBookInfo();
	}
	
	public void play() {
		if (mBook == null) {
			throw new IllegalStateException("Cannot play when no book has been previously set");
		}
		play(mBook.getId(), mBook.getPosition().toString());
	}

	public void play(final String bookId, final String positionText) {
		Log.i(PlayerApplication.TAG, String.format("Starting play of book: %s,  Position: %s", bookId, positionText));
		final BigDecimal position = new BigDecimal(positionText);
		new GetBookTask().execute(new AbstractTask.SimpleTaskListener<Book>() {

			@Override
			public void success(final Book book) {
				if (book != null) {
					mStreamingThread.task.eject();
					mBook = book;
					book.setPosition(position);
					mCurrentEnd = book.getCurrentFragment().getBookStartPosition();
					if (isPlaying()) {
						stop();
					}
					synchronized (mNextPlayerThread) {
						mNextPlayerThread.notify();
					}
					synchronized (mStreamingThread) {
						mStreamingThread.notify();
					}
				} else {
					fireEvent(Event.PLAY_FAILED, "No book was found for id: " + bookId);
				}
			}
		}, bookId);
	}
	
	public boolean isPlaying() {
		try {
			return mCurrentPlayer != null && mCurrentPlayer.isPlaying();
		} catch(Exception ignore) {
		}
		return false;
	}

	public void cacheBook(String bookId) {
		Book book = PlayerApplication.getInstance().getBookService().getBook(bookId);
		if (book != null) {
			mDownloaderThread.addBook(book);
		}
	}

	public void stop() {
		stop(true);
	}

//	public void pause() {
//		if (isPlaying()) {
//			mCurrentPlayer.pause();
//		} else if (mCurrentPlayer != null) {
//			mLockScreenManager.play();
//			mNotificationManager.notifyPlaying(mBook);
//			mCurrentPlayer.start();
//			synchronized (mProgressThread) {
//				mProgressThread.notify();
//			}
//		}
//	}
	
	public void next() {
		Section nextSection = mBook.nextSection(mBook.getPosition());
		String bookId = mBook.getId(); 
		stop(false);
		play(bookId, nextSection.getOffset().toString());
	}
	
	public void previous() {
		Section previousSection = mBook.previousSection(mBook.getPosition());
		String bookId = mBook.getId(); 
		stop(false);
		play(bookId, previousSection.getOffset().toString());
	}

	private class StreamingThread extends WorkerThread {

		private long FIVE_MINUTES = 1000 * 60 * 5;
		private StreamBiteTask task = new StreamBiteTask();
		private boolean mBusy = false;
		
		public StreamingThread() {
			super("Streamer");
		}

		@Override
		public void run() {
			while(running()) {
				if (mBook == null) {
					waitUp("Sleeping since no book has been set");
				}
				if (mBook != null && mOnline) {
					SoundBite bite = null;
					do {
						if (mOnline == false) {
							waitUp("Not online. Going to sleep");
						}
						mDownloaderThread.giveWay();
						mBusy = true;
						BigDecimal currentPosition = isPlaying() ? new BigDecimal(mCurrentPlayer.getCurrentPosition()).divide(THOUSAND) : BigDecimal.ZERO ;
						bite = task.doCaching(mBook, currentPosition, getExpectedCompletion());
						synchronized (mNextPlayerThread) {
							mNextPlayerThread.notify();
						}
					} while(bite != null);
					mBusy = false;
					synchronized (mDownloaderThread) {
						mDownloaderThread.notify();
					}
					waitUp(FIVE_MINUTES, "Streaming has nothing to do. Going to sleep");
				}
			}
		}
		
		boolean isStreaming() {
			return mBusy;
		}
	}
	
	private class NextPlayerThread extends WorkerThread {
		
		public NextPlayerThread() {
			super("NextPlayer");
		}
		
		@Override
		public void run() {
			while (running()) {
				if (mNextPlayer != null) {
					waitUp("Falling a sleep as next bite is already prepared");
				}
				if (mBook == null) {
					waitUp("Next player thread has nothing to do , as no book has been selected");
				} else {
					SoundFragment fragment = mBook.getFragment(mCurrentEnd);
					SoundBite bite = fragment.getBite(mCurrentEnd);
					if (bite == null) {
						waitUp("Falling a sleep as no bite is available");
					} else if (mNextPlayer == null){
						Log.i(PlayerApplication.TAG, "Next player will be from fragment url: " + fragment.getUrl());
						try {
							Log.i(PlayerApplication.TAG, String.format("In fragment: %s-%s of %s In book: %s-%s",
									bite.getStart(), bite.getEnd(), fragment.getEnd(),
									fragment.getPosition(bite.getStart()), fragment.getPosition(bite.getEnd())));
							mCurrentEnd = mCurrentEnd.add(bite.getDuration());
							if (bite.getEnd().compareTo(fragment.getEnd()) == 0) {
								Log.i(PlayerApplication.TAG, "Last bite. Adjusting current end with: " + fragment.getBookEndPosition().subtract(fragment.getBookStartPosition().add(fragment.getEnd())));
								mCurrentEnd = fragment.getBookEndPosition();
							}
							if (mCurrentPlayer != null) {
								mNextPlayer = new MediaPlayer(mCurrentEnd.subtract(bite.getDuration()), mCurrentEnd);
								setDataSource(mNextPlayer, bite);
								mNextPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC);
								mNextPlayer.prepare();
								mCurrentPlayer.setNextMediaPlayer(mNextPlayer);
							} else {
								startPlayer(bite, mCurrentEnd);
							}
						} catch (Exception e) {
							Log.e(PlayerApplication.TAG, "Unable to queue the next player", e);
						}
					}				
				}
			}
		}
	}
	
	private class ProgressThread extends WorkerThread {
		public ProgressThread() {
			super("Progress");
		}
		
		@Override
		public void run() {
			while (running()) {
				if (isPlaying() == false) {
					waitUp("No progress as no book is playing. Going to sleep");
				} else {
					BigDecimal currentPosition = mCurrentPlayer.getCurrentPosition() > 0 ? new BigDecimal(mCurrentPlayer.getCurrentPosition()).divide(THOUSAND) : BigDecimal.ZERO;
					mBook.setPosition(mCurrentPlayer.getStart().add(currentPosition));
			    	fireEvent(Event.PLAY_TIME_UPDATE, mBook.getId(), mBook.getPosition());
				}
				waitUp(100);
			}
		}
	}

	@Override
	public void downloadFailed(Book book, String reason) {
		fireEvent(Event.DOWNLOAD_FAILED, book.getId(), reason);
	}
	
	@Override
	public void downloadCompleted(Book book) {
		fireEvent(Event.DOWNLOAD_COMPLETED, book.getId());
	}
	
	@Override
	public void downloadProgress(Book book, BigDecimal percentage) {
		fireEvent(Event.DOWNLOAD_PROGRESS, percentage);
	}
	
	@Override
	public boolean isBusy() {
		return mStreamingThread.isStreaming();
	}

	public void onCompletion(android.media.MediaPlayer mp) {
		if (mp != mCurrentPlayer) {
			throw new IllegalStateException("How did that happen?!");
		}
		mBook.setPosition(mCurrentPlayer.getEnd());
		Log.i(PlayerApplication.TAG, "New book position: " + mBook.getPosition());
		MediaPlayer releaseIt = mCurrentPlayer;
		mCurrentPlayer = mNextPlayer;
		mNextPlayer = null;
		if (mCurrentPlayer != null) {
			mCurrentPlayer.setOnCompletionListener(this);
			synchronized (mProgressThread) {
				mProgressThread.notify();
			}
			mNotificationManager.notifyChapterChange(mBook);
			mLockScreenManager.changeChapter();
		}
		synchronized (mNextPlayerThread) {
			mNextPlayerThread.notify();
		}
		releaseIt.reset();
		releaseIt.release();
	}

	private void startPlayer(SoundBite bite, BigDecimal end) {
		int seekTo = mBook.getCurrentFragment().getOffset(mBook.getPosition()).multiply(THOUSAND).intValue();
		Log.i(PlayerApplication.TAG, "Creating new start, and adjusting player position to: " + seekTo);
		try {
			int audioFocusResult = mAudioManager.requestAudioFocus(this, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN);
			if (audioFocusResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
				mLockScreenManager.initialize(mBook);
			} else {
				Log.w(PlayerApplication.TAG, "Unable gain audio focus. Abandon playing og book");
				return;
			}
			mCurrentPlayer = new MediaPlayer(end.subtract(bite.getDuration()), end);
			setDataSource(mCurrentPlayer, bite);
			mCurrentPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC);
			mCurrentPlayer.prepare();
			mCurrentPlayer.seekTo(seekTo);
			mCurrentPlayer.setOnCompletionListener(BookPlayer.this);
			Log.i(PlayerApplication.TAG, "Length : " + mCurrentPlayer.getDuration());
			mCurrentPlayer.start();
			mNotificationManager.notifyPlaying(mBook);
			synchronized (mProgressThread) {
				mProgressThread.notify();
			}
		} catch (Exception e) {
			Log.e(PlayerApplication.TAG, "Error occured while starting player", e);
		}
		
	}
	public void stop(boolean fullStop) {
		if(mCurrentPlayer != null) {
			mCurrentPlayer.stop();
			mCurrentPlayer.release();
			mCurrentPlayer = null;
		}
		if (mNextPlayer != null) {
			mNextPlayer.release();
			mNextPlayer = null;
		}
		if (mBook != null) {
			mNotificationManager.notifyPause(mBook);
			PlayerApplication.getInstance().getBookService().updateBook(mBook);
			if (fullStop) mBook = null;
		}
		if (fullStop) {
			mAudioManager.abandonAudioFocus(this);
			mLockScreenManager.stop();
		} else {
			mLockScreenManager.pause();
		}
	}
	
	private long getExpectedCompletion() {
		if (mBook != null) {
			BigDecimal remainingPlaytime = mCurrentEnd.multiply(THOUSAND).subtract(mBook.getPosition().multiply(THOUSAND));
			Log.i(PlayerApplication.TAG, "Expected completion " +  remainingPlaytime.divide(THOUSAND)  + " seconds");
			return remainingPlaytime.longValue() + System.currentTimeMillis();
		} 
		return 0;
	}
	
	private void setDataSource(MediaPlayer player, SoundBite bite) {
		FileInputStream stream = null;
		try {
			stream = openFileInput(bite.getFilename());
			player.setDataSource(stream.getFD());
		} catch (IOException e) {
			Log.e(PlayerApplication.TAG, "Unable to open bite filename: " + bite.getFilename(), e);
		} finally {
			if (stream != null) {
				try {
					stream.close();
				} catch (IOException e) {
					Log.e(PlayerApplication.TAG, "Unable to close bite: " + bite.getFilename(), e);
				}
			}
		}
	}

	private void listenToConnectivity() {
		mNetworkStateReceiver = new BroadcastReceiver() {

		    @Override
		    public void onReceive(Context context, Intent intent) {
		    	mOnline = intent.getBooleanExtra(ConnectivityManager.EXTRA_NO_CONNECTIVITY, false) == false;
		    	Log.i(PlayerApplication.TAG, mOnline ? "Device is online" : "Device is offline");
		    	if (mOnline) {
		    		synchronized (mStreamingThread) {
		    			mStreamingThread.notify();
		    		}
		    	}
		    }
		};
		IntentFilter filter = new IntentFilter(ConnectivityManager.CONNECTIVITY_ACTION);        
		PlayerApplication.getInstance().registerReceiver(mNetworkStateReceiver, filter);
	}
	
	private void unlistenToConnectivity() {
		PlayerApplication.getInstance().unregisterReceiver(mNetworkStateReceiver);
	}

	private void fireEvent(final Event event, final Object ... params) {
		if (mEventListener != null) {
			mEventListener.onEvent(event, params);
		}
	}

	private FileInputStream openFileInput(String filename) throws FileNotFoundException {
		return PlayerApplication.getInstance().openFileInput(filename);
	}
	
	@Override
	public void onAudioFocusChange(int focusChange) {
		if (focusChange == AudioManager.AUDIOFOCUS_GAIN) {
            // Resume playback 
        } else if (focusChange == AudioManager.AUDIOFOCUS_LOSS) {
            stop();
        }		
	}
}