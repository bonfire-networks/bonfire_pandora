const VidstackHook = {
    mounted() {
      console.log("Vidstack Hook mounted");
      
      // Import the necessary elements
      import('vidstack/elements').then((Vidstack) => {
        console.log("Available Vidstack exports:", Object.keys(Vidstack));
        
        // Define custom elements
        const { defineCustomElement } = Vidstack;
        defineCustomElement(Vidstack.MediaPlayerElement);
        defineCustomElement(Vidstack.MediaProviderElement);
        defineCustomElement(Vidstack.MediaControlsElement);
        
        console.log("All Vidstack elements defined");
        
        // Initialize player after a short delay
        setTimeout(() => {
          this.initPlayer();
        }, 300);
      }).catch(err => {
        console.error("Error loading Vidstack elements:", err);
      });
    },
    
    initPlayer() {
      // Get player element
      this.player = this.el.querySelector('media-player');
      
      if (!this.player) {
        console.error("Media player element not found");
        return;
      }
      
      console.log("Initializing player:", this.player);
      
      // Get the video element
      this.videoElement = this.el.querySelector('video');
      if (!this.videoElement) {
        console.error("Video element not found");
        return;
      }
      
      // Get UI elements
      this.playButton = this.el.querySelector('[data-action="play-pause"]');
      this.playIcon = this.el.querySelector('.play-icon');
      this.pauseIcon = this.el.querySelector('.pause-icon');
      
      this.muteButton = this.el.querySelector('[data-action="mute"]');
      this.mutedIcon = this.el.querySelector('.muted-icon');
      this.unmutedIcon = this.el.querySelector('.unmuted-icon');
      
      this.fullscreenButton = this.el.querySelector('[data-action="fullscreen"]');
      
      this.currentTimeDisplay = this.el.querySelector('.current-time');
      this.durationDisplay = this.el.querySelector('.duration');
      this.timeSlider = this.el.querySelector('.time-slider');
      
      // Initialize controls state
      this.initializeControlsState();
      
      // Set up event handlers
      this.setupControlHandlers();
      
      // Setup custom control buttons
      this.setupCustomControls();
      
      // Set up event listeners for state updates
      this.setupStateListeners();
    },
    
    initializeControlsState() {
      // Set initial button states
      this.updatePlayPauseState(this.videoElement.paused);
      this.updateMuteState(this.videoElement.muted);
      
      // Set initial time display
      this.videoElement.addEventListener('loadedmetadata', () => {
        console.log('Metadata loaded, duration:', this.videoElement.duration);
        this.updateTimeDisplay();
        this.updateTimeSlider();
        
        // Set max value for time slider
        if (this.timeSlider && !isNaN(this.videoElement.duration)) {
          this.timeSlider.max = this.videoElement.duration;
        }
      });
    },
    
    setupControlHandlers() {
      // Play/Pause button
      if (this.playButton) {
        this.playButton.addEventListener('click', () => {
          console.log("Play/Pause button clicked");
          if (this.videoElement.paused) {
            this.videoElement.play().catch(error => {
              console.error("Play error:", error);
            });
          } else {
            this.videoElement.pause();
          }
        });
      }
      
      // Mute button
      if (this.muteButton) {
        this.muteButton.addEventListener('click', () => {
          console.log("Mute button clicked");
          this.videoElement.muted = !this.videoElement.muted;
        });
      }
      
      // Fullscreen button
      if (this.fullscreenButton) {
        this.fullscreenButton.addEventListener('click', () => {
          console.log("Fullscreen button clicked");
          if (document.fullscreenElement) {
            document.exitFullscreen().catch(error => {
              console.error("Exit fullscreen error:", error);
            });
          } else {
            this.player.requestFullscreen().catch(error => {
              console.error("Enter fullscreen error:", error);
            });
          }
        });
      }
      
      // Time slider
      if (this.timeSlider) {
        // Update time when dragging
        this.timeSlider.addEventListener('input', () => {
          // Update time display while dragging
          this.updateCurrentTimeDisplay(parseFloat(this.timeSlider.value));
        });
        
        // Seek when slider is released
        this.timeSlider.addEventListener('change', () => {
          const newTime = parseFloat(this.timeSlider.value);
          console.log("Seeking to:", newTime);
          this.videoElement.currentTime = newTime;
        });
      }
    },
    
    setupStateListeners() {
      // Play/Pause state
      this.videoElement.addEventListener('play', () => {
        console.log('Video playing');
        this.updatePlayPauseState(false);
      });
      
      this.videoElement.addEventListener('pause', () => {
        console.log('Video paused');
        this.updatePlayPauseState(true);
      });
      
      // Mute state
      this.videoElement.addEventListener('volumechange', () => {
        this.updateMuteState(this.videoElement.muted);
      });
      
      // Time updates
      this.videoElement.addEventListener('timeupdate', () => {
        this.updateTimeDisplay();
        this.updateTimeSlider();
      });
      
      // Duration updates
      this.videoElement.addEventListener('durationchange', () => {
        console.log('Duration changed:', this.videoElement.duration);
        this.updateTimeDisplay();
        
        // Update time slider max
        if (this.timeSlider && !isNaN(this.videoElement.duration)) {
          this.timeSlider.max = this.videoElement.duration;
        }
      });
    },
    
    updatePlayPauseState(isPaused) {
      if (this.playIcon && this.pauseIcon) {
        this.playIcon.style.display = isPaused ? 'inline' : 'none';
        this.pauseIcon.style.display = isPaused ? 'none' : 'inline';
      }
    },
    
    updateMuteState(isMuted) {
      if (this.mutedIcon && this.unmutedIcon) {
        this.mutedIcon.style.display = isMuted ? 'inline' : 'none';
        this.unmutedIcon.style.display = isMuted ? 'none' : 'inline';
      }
    },
    
    updateTimeDisplay() {
      const currentTime = this.videoElement.currentTime;
      const duration = this.videoElement.duration;
      
      if (this.currentTimeDisplay) {
        this.currentTimeDisplay.textContent = this.formatTime(currentTime);
      }
      
      if (this.durationDisplay && !isNaN(duration)) {
        this.durationDisplay.textContent = this.formatTime(duration);
      }
    },
    
    updateCurrentTimeDisplay(time) {
      if (this.currentTimeDisplay) {
        this.currentTimeDisplay.textContent = this.formatTime(time);
      }
    },
    
    updateTimeSlider() {
      if (this.timeSlider && !isNaN(this.videoElement.currentTime)) {
        this.timeSlider.value = this.videoElement.currentTime;
      }
    },
    
    formatTime(seconds) {
      if (isNaN(seconds) || !isFinite(seconds)) {
        return '0:00';
      }
      
      const mins = Math.floor(seconds / 60);
      const secs = Math.floor(seconds % 60);
      return `${mins}:${secs.toString().padStart(2, '0')}`;
    },
    
    setupCustomControls() {
      const inButton = this.el.querySelector('[data-action="mark-in"]');
      const outButton = this.el.querySelector('[data-action="mark-out"]');
      
      if (inButton) {
        inButton.addEventListener('click', () => {
          const timestamp = this.videoElement.currentTime;
          console.log("IN timestamp:", timestamp);
          this.pushEvent('mark_in_timestamp', { timestamp });
        });
      }
      
      if (outButton) {
        outButton.addEventListener('click', () => {
          const timestamp = this.videoElement.currentTime;
          console.log("OUT timestamp:", timestamp);
          this.pushEvent('mark_out_timestamp', { timestamp });
        });
      }
    }
};

export default VidstackHook;