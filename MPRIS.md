Useful
*Unused*

# Implementation
## MediaPlayer2

### Methods
- [x] Raise *Unused*
- [x] Quit

### Properties
- [x] CanQuit true
- [x] Fullscreen *Unused*
- [x] CanFullscreen false
- [x] CanRaise false
- [ ] HasTracklist *TODO*
- [x] Identity smd
- [x] DesktopEntry smd
- [ ] SupportedUriSchemes *TODO*
- [ ] SupportedMimeTypes *TODO*

## MediaPlayer2.Player

### Methods
- [x] Next
- [x] Previous
- [x] Pause
- [x] PlayPause
- [ ] Stop
- [x] Play
- [x] Seek
- [x] SetPosition
- [x] OpenUri

### Signals
- [ ] Seeked

### Properties
- [ ] PlaybackStatus
- [ ] LoopStatus
- [ ] Rate
- [ ] Shuffle
- [ ] Metadata_Map
- [ ] Volume
- [ ] Position
- [ ] MinimumRate
- [ ] MaximumRate
- [ ] CanGoNext
- [ ] CanGoPrevious
- [ ] CanPlay
- [ ] CanPause
- [ ] CanSeek
- [ ] CanControl

### Types
- [ ] Track_Id
- [ ] Playback_Rate
- [ ] Volume
- [ ] Time_In_Us
- [ ] Playback_Status
- [ ] LoopStatus

## MediaPlayer2.TrackList

### Methods
- [ ] GetTracksMetadata
- [ ] AddTrack
- [ ] RemoveTrack
- [ ] GoTo

### Signals
- [ ] TrackListReplaced
- [ ] TrackAdded
- [ ] TrackRemoved
- [ ] TrackMetadataChanged

### Properties
- [ ] Tracks
- [ ] CanEditTracks

### Types
- [ ] Uri
- [ ] Metadata_Map

## MediaPlayer2.Playlists

### Methods
- [ ] ActivatePlaylist
- [ ] GetPlaylists

### Signals
- [ ] PlaylistChanged

### Properties
- [ ] PlaylistCount
- [ ] Orderings
- [ ] ActivatePlaylist

### Types
- [ ] Playlist_Id
- [ ] Uri
- [ ] Playlist_Ordering
- [ ] Playlist
- [ ] Maybe_Playlist

# Interface
## MediaPlayer2

### Methods
- [ ] Raise
- [ ] Quit

### Properties
- [ ] CanQuit
- [ ] Fullscreen
- [ ] CanFullscreen
- [ ] CanRaise
- [ ] HasTracklist
- [ ] Identity
- [ ] DesktopEntry
- [ ] SupportedUriSchemes
- [ ] SupportedMimeTypes

## MediaPlayer2.Player

### Methods
- [ ] Next
- [ ] Previous
- [ ] Pause
- [ ] PlayPause
- [ ] Stop
- [ ] Play
- [ ] Seek
- [ ] SetPosition
- [ ] OpenUri

### Signals
- [ ] Seeked

### Properties
- [ ] PlaybackStatus
- [ ] LoopStatus
- [ ] Rate
- [ ] Shuffle
- [ ] Metadata_Map
- [ ] Volume
- [ ] Position
- [ ] MinimumRate
- [ ] MaximumRate
- [ ] CanGoNext
- [ ] CanGoPrevious
- [ ] CanPlay
- [ ] CanPause
- [ ] CanSeek
- [ ] CanControl

### Types
- [ ] Track_Id
- [ ] Playback_Rate
- [ ] Volume
- [ ] Time_In_Us
- [ ] Playback_Status
- [ ] LoopStatus

## MediaPlayer2.TrackList

### Methods
- [ ] GetTracksMetadata
- [ ] AddTrack
- [ ] RemoveTrack
- [ ] GoTo

### Signals
- [ ] TrackListReplaced
- [ ] TrackAdded
- [ ] TrackRemoved
- [ ] TrackMetadataChanged

### Properties
- [ ] Tracks
- [ ] CanEditTracks

### Types
- [ ] Uri
- [ ] Metadata_Map

## MediaPlayer2.Playlists

### Methods
- [ ] ActivatePlaylist
- [ ] GetPlaylists

### Signals
- [ ] PlaylistChanged

### Properties
- [ ] PlaylistCount
- [ ] Orderings
- [ ] ActivatePlaylist

### Types
- [ ] Playlist_Id
- [ ] Uri
- [ ] Playlist_Ordering
- [ ] Playlist
- [ ] Maybe_Playlist
