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
            this.setupTimestampBadgeClickHandlers();
          }, 300);
        }).catch(err => {
          console.error("Error loading Vidstack elements:", err);
        });
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
        
        // NEW: Explicitly set preload attribute to ensure metadata loads
        this.videoElement.preload = "metadata";
        
        // Initialize controls state
        this.initializeControlsState();
        
        // Set up event handlers
        this.setupControlHandlers();
        
        // Setup custom control buttons
        this.setupCustomControls();
        
        // Set up event listeners for state updates
        this.setupStateListeners();
        
        // Ensure metadata is loaded
        this.ensureMetadataLoaded();
      },
      
    
      ensureMetadataLoaded() {
        console.log("Ensuring metadata is loaded, current readyState:", this.videoElement.readyState);
        
        // If metadata isn't loaded yet, force it to load
        if (this.videoElement.readyState === 0) {
          this.videoElement.load();
        }
        
        // If duration is already available, use it
        if (this.videoElement.duration && !isNaN(this.videoElement.duration)) {
          this.updateDurationDisplay(this.videoElement.duration);
          
          if (this.timeSlider) {
            console.log("Setting time slider max to full duration:", this.videoElement.duration);
            this.timeSlider.max = this.videoElement.duration;
          }
        }
        
        // NEW: Force a small seek to trigger metadata loading in some browsers
        if (!this.videoElement.duration || isNaN(this.videoElement.duration)) {
          // Try to trigger metadata loading by doing a small seek
          try {
            // Save current state
            const wasPaused = this.videoElement.paused;
            
            // Seek to 0.1 seconds to force metadata loading
            this.videoElement.currentTime = 0.1;
            
            // If it was paused, make sure it stays paused
            if (wasPaused) {
              this.videoElement.pause();
            }
          } catch (e) {
            console.warn("Could not perform initial seek:", e);
          }
        }
        
        // Add a series of fallback checks to ensure duration is displayed
        const checkDuration = () => {
          if (this.videoElement.duration && !isNaN(this.videoElement.duration)) {
            console.log("Duration check successful:", this.videoElement.duration);
            this.updateDurationDisplay(this.videoElement.duration);
            
            if (this.timeSlider) {
              this.timeSlider.max = this.videoElement.duration;
            }
            return true;
          }
          return false;
        };
        
        // Check after increasing delays if needed
        setTimeout(() => {
          if (!checkDuration()) {
            setTimeout(() => {
              if (!checkDuration()) {
                setTimeout(checkDuration, 1000);
              }
            }, 500);
          }
        }, 200);
      },
    
      initializeControlsState() {
        // Set initial button states
        this.updatePlayPauseState(this.videoElement.paused);
        this.updateMuteState(this.videoElement.muted);
        
        // Set initial time display
        this.updateTimeDisplay();
        
        // Set initial time display when metadata loads
        this.videoElement.addEventListener('loadedmetadata', () => {
          console.log('Metadata loaded, duration:', this.videoElement.duration);
          this.updateTimeDisplay();
          this.updateTimeSlider();
          
          // Update duration display specifically
          this.updateDurationDisplay(this.videoElement.duration);
          
          // Set max value for time slider
          if (this.timeSlider && !isNaN(this.videoElement.duration)) {
            console.log("Setting time slider max to:", this.videoElement.duration);
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
        // *** MODIFIED: Add logging to debug slider range ***
        this.timeSlider.addEventListener('input', () => {
          const value = parseFloat(this.timeSlider.value);
          console.log(`Slider input: ${value} / max: ${this.timeSlider.max}`);
          this.updateCurrentTimeDisplay(value);
        });
        
        this.timeSlider.addEventListener('change', () => {
          const newTime = parseFloat(this.timeSlider.value);
          console.log(`Seeking to: ${newTime} / max: ${this.timeSlider.max}`);
          
          // *** MODIFIED: Add validation to ensure the seek time is valid ***
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
        console.log('Duration changed:', this.videoElement.duration);
        this.updateTimeDisplay();
        
        // *** MODIFIED: Add more detailed logging ***
        if (this.timeSlider && !isNaN(this.videoElement.duration)) {
          console.log("Updating time slider max to:", this.videoElement.duration);
          this.timeSlider.max = this.videoElement.duration;
          
          // Verify the setting took effect
          setTimeout(() => {
            console.log("Time slider max is now:", this.timeSlider.max);
          }, 100);
        }
      });
      
      // *** NEW: Add canplay listener as a backup ***
      this.videoElement.addEventListener('canplay', () => {
        console.log('Video can play, checking duration:', this.videoElement.duration);
        
        // One more check to ensure slider range is correct
        if (this.timeSlider && this.videoElement.duration > 0 && 
            (!this.timeSlider.max || parseFloat(this.timeSlider.max) < this.videoElement.duration)) {
          console.log("Setting time slider max during canplay:", this.videoElement.duration);
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