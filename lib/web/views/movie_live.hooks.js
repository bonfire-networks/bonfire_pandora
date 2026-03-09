const VidstackHook = {
    mounted() {
        console.log("Movie player hook mounted");
        this.initPlayer();
        this.setupTimestampBadgeClickHandlers();
      },
    

      setupTimestampBadgeClickHandlers() {
        // Find all timestamp badges in the document
        const annotations = document.querySelectorAll('[data-role=annotation-checkpoint]');
        annotations.forEach(badge => {
          badge.addEventListener('click', (event) => {
              const inTimeSeconds = parseFloat(badge.dataset.in) || parseFloat(badge.dataset.out);
              
              if (!isNaN(inTimeSeconds) && this.videoElement) {
                console.log("Seeking to timestamp:", inTimeSeconds);
                this.videoElement.currentTime = inTimeSeconds;
                
                // Auto-play after seeking (optional)
                this.videoElement.play().catch(error => {
                  console.error("Could not auto-play after seeking:", error);
                });
              }
          });
      })
    },

      initPlayer() {
        // Get the video element
        this.videoElement = this.el.querySelector('video');
        if (!this.videoElement) {
          console.error("Video element not found");
          return;
        }

        // Use the wrapping shell for fullscreen, fall back to the video element itself.
        this.player = this.el.querySelector('[data-role="movie-player-shell"]') || this.videoElement;
        console.log("Initializing player:", this.player);
        
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
        this.updateTimeDisplay();
        
        // Set initial time display when metadata loads
        this.videoElement.addEventListener('loadedmetadata', () => {
          this.updateTimeDisplay();
          this.updateTimeSlider();
          
          // Update duration display specifically
          this.updateDurationDisplay(this.videoElement.duration);
          
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
          this.videoElement.muted = !this.videoElement.muted;
        });
      }
      
      // Fullscreen button
      if (this.fullscreenButton) {
        this.fullscreenButton.addEventListener('click', () => {
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
        this.timeSlider.addEventListener('input', () => {
          const value = parseFloat(this.timeSlider.value);
          this.updateCurrentTimeDisplay(value);
        });
        
        this.timeSlider.addEventListener('change', () => {
          const newTime = parseFloat(this.timeSlider.value);

          if (!isNaN(newTime) && isFinite(newTime) && newTime >= 0) {
            this.videoElement.currentTime = newTime;
          }
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
        this.updateTimeDisplay();
        
        if (this.timeSlider && !isNaN(this.videoElement.duration)) {
          this.timeSlider.max = this.videoElement.duration;
        }
      });
    },
    
    updatePlayPauseState(isPaused) {
      if (this.playIcon && this.pauseIcon) {
        this.playIcon.style.display = isPaused ? 'inline' : 'none';
        this.pauseIcon.style.display = isPaused ? 'none' : 'flex';
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
        
        // Update duration display if available
        if (duration && !isNaN(duration)) {
          this.updateDurationDisplay(duration);
        }
      },
      
      // NEW: Separate function for updating just the duration display
      updateDurationDisplay(duration) {
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
        // *** MODIFIED: Only update if not being dragged ***
        if (document.activeElement !== this.timeSlider) {
          this.timeSlider.value = this.videoElement.currentTime;
        }
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
      const nextFrameButton = this.el.querySelector('[data-action="next-frame"]');
      const prevFrameButton = this.el.querySelector('[data-action="prev-frame"]');
      
      if (inButton) {
        inButton.addEventListener('click', () => {
          const timestamp = this.videoElement.currentTime;
          console.log("IN timestamp:", timestamp);
          this.pushEvent('mark_in_timestamp', { timestamp: timestamp });
        });
      }
      
      if (outButton) {
        outButton.addEventListener('click', () => {
          const timestamp = this.videoElement.currentTime;
          console.log("OUT timestamp:", timestamp);
          this.pushEvent('mark_out_timestamp', { timestamp: timestamp });
        });
      }

      // Next frame button
      if (nextFrameButton) {
        nextFrameButton.addEventListener('click', () => {
          this.stepForward();
        });
      }

      // Previous frame button
      if (prevFrameButton) {
        prevFrameButton.addEventListener('click', () => {
          this.stepBackward();
        });
      }
    },

    // Calculate frame duration based on video fps or use default
    getFrameDuration() {
      // Use standard 25 fps (1/25 = 0.04 seconds per frame) or allow custom setting
      const fps = this.fps || 25; // Default to 25 fps if not specified
      return 1 / fps;
    },

    // Step forward one frame
    stepForward() {
      if (!this.videoElement) return;
      
      // Pause the video if it's playing
      if (!this.videoElement.paused) {
        this.videoElement.pause();
      }
      
      const frameDuration = this.getFrameDuration();
      const newTime = Math.min(this.videoElement.currentTime + frameDuration, this.videoElement.duration);
      
      console.log(`Stepping forward one frame (${frameDuration.toFixed(3)}s) to ${newTime.toFixed(3)}s`);
      this.videoElement.currentTime = newTime;
    },

    // Step backward one frame
    stepBackward() {
      if (!this.videoElement) return;
      
      // Pause the video if it's playing
      if (!this.videoElement.paused) {
        this.videoElement.pause();
      }
      
      const frameDuration = this.getFrameDuration();
      const newTime = Math.max(this.videoElement.currentTime - frameDuration, 0);
      
      console.log(`Stepping backward one frame (${frameDuration.toFixed(3)}s) to ${newTime.toFixed(3)}s`);
      this.videoElement.currentTime = newTime;
    },
};

export default VidstackHook;