/**
 * PandoraTimelineStrip
 *
 * Mounts the antialias timeline strip below the Plyr movie player and:
 *   - subscribes to Plyr `timeupdate` / `loadedmetadata` events through the
 *     `pandora:movie-player:ready` window event dispatched by
 *     `PandoraMoviePlayer`, so this hook stays decoupled from the player.
 *   - moves a position indicator according to the current play head.
 *   - implements click + pointer-drag-to-seek across the strip width.
 *   - delegates clicks on `[data-role=annotation-checkpoint]` markers to the
 *     player (`PandoraMoviePlayer` already handles that delegation; this hook
 *     just uses the same data-attributes so styling stays consistent).
 *   - hides the strip if the timeline image returns a 404 (graceful fallback
 *     when Pandora has not yet generated the strip for the movie).
 *
 * The hook avoids touching annotation markers' inline styles (Surface owns
 * them) — it only mutates the position indicator.
 */

const POSITION_ID = "timeline_strip_position";

function clamp(n, min, max) {
  if (Number.isNaN(n)) return min;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

function ratioFromPointer(rect, clientX) {
  if (!rect || rect.width <= 0) return 0;
  return clamp((clientX - rect.left) / rect.width, 0, 1);
}

const PandoraTimelineStrip = {
  mounted() {
    this.indicator = this.el.querySelector(`#${POSITION_ID}`);
    this.img = this.el.querySelector("img.timeline-strip-img");
    this.duration = parseFloat(this.el.dataset.duration) || NaN;
    this.targetPlayerId = this.el.dataset.targetPlayer || "movie_player_root";
    this.fallbackSrc = this.el.dataset.fallbackSrc || "";
    this.fallbackUsed = false;
    this.player = null;
    this.video = null;
    this.dragging = false;

    this.attachImageFallback();
    this.attachPointerSeek();
    this.attachPlayerListeners();
    this.attachKeyboardSeek();
  },

  destroyed() {
    this.detachPlayerEvents();
    if (this.onMoviePlayerReady) {
      window.removeEventListener("pandora:movie-player:ready", this.onMoviePlayerReady);
      this.onMoviePlayerReady = null;
    }
    if (this.onMoviePlayerDestroyed) {
      window.removeEventListener("pandora:movie-player:destroyed", this.onMoviePlayerDestroyed);
      this.onMoviePlayerDestroyed = null;
    }
    if (this.onPointerMove) {
      window.removeEventListener("pointermove", this.onPointerMove);
      this.onPointerMove = null;
    }
    if (this.onPointerUp) {
      window.removeEventListener("pointerup", this.onPointerUp);
      this.onPointerUp = null;
    }
  },

  // Pandora always generates the 64p full-strip preview, but legacy items may
  // miss the resized 16p variant (only built by `join_tiles`). We try the
  // small preview first and, on failure, swap to the large one. If neither
  // loads we hide the strip so we never leave a broken/alt-text-only image.
  //
  // `complete && naturalWidth === 0` covers the timing edge case where the
  // <img> already finished loading (and emitted its `error` event) before the
  // hook could attach a listener — common with `loading="eager"` on a small
  // JPEG that 404s instantly.
  attachImageFallback() {
    if (!this.img) return;

    this.img.addEventListener("error", this.onImageError.bind(this));
    this.img.addEventListener("load", this.onImageLoad.bind(this));

    if (this.img.complete) {
      if (this.img.naturalWidth === 0) {
        this.onImageError();
      } else {
        this.onImageLoad();
      }
    }
  },

  onImageLoad() {
    if (this.img && this.img.naturalWidth === 0) {
      // Some servers reply 200 with an empty/invalid body — treat as error.
      this.onImageError();
      return;
    }
    this.el.classList.remove("timeline-strip-root--unavailable");
    this.el.removeAttribute("aria-hidden");
  },

  onImageError() {
    if (!this.fallbackUsed && this.fallbackSrc && this.img) {
      this.fallbackUsed = true;
      this.img.src = this.fallbackSrc;
      return;
    }
    this.el.classList.add("timeline-strip-root--unavailable");
    this.el.setAttribute("aria-hidden", "true");
  },

  attachPlayerListeners() {
    this.onMoviePlayerReady = (event) => {
      const { hookId, player, video } = event.detail || {};
      if (hookId && hookId !== this.targetPlayerId) return;
      this.bindPlayer(player, video);
    };
    this.onMoviePlayerDestroyed = (event) => {
      const { hookId } = event.detail || {};
      if (hookId && hookId !== this.targetPlayerId) return;
      this.detachPlayerEvents();
      this.player = null;
      this.video = null;
    };
    window.addEventListener("pandora:movie-player:ready", this.onMoviePlayerReady);
    window.addEventListener("pandora:movie-player:destroyed", this.onMoviePlayerDestroyed);

    // The player may have mounted before this hook (LiveView mount order is
    // not guaranteed). Try to resolve it eagerly.
    const root = document.getElementById(this.targetPlayerId);
    if (root) {
      const video = root.querySelector("video.player");
      const player = video?.plyr;
      if (player && video) this.bindPlayer(player, video);
    }
  },

  bindPlayer(player, video) {
    if (!player || !video || this.player === player) return;
    this.detachPlayerEvents();
    this.player = player;
    this.video = video;

    this.onTimeUpdate = () => this.refreshIndicator();
    this.onMetadata = () => {
      // Prefer the explicit server-side duration (Pandora item duration), but
      // fall back to the player's own metadata when it becomes available.
      if (!Number.isFinite(this.duration) || this.duration <= 0) {
        const d = this.player?.duration;
        if (Number.isFinite(d) && d > 0) {
          this.duration = d;
          this.el.dataset.duration = String(d);
        }
      }
      this.refreshIndicator();
    };

    this.player.on("timeupdate", this.onTimeUpdate);
    this.player.on("seeked", this.onTimeUpdate);
    this.player.on("loadedmetadata", this.onMetadata);
    this.player.on("ready", this.onMetadata);

    this.refreshIndicator();
  },

  detachPlayerEvents() {
    if (!this.player) return;
    try {
      if (this.onTimeUpdate) {
        this.player.off?.("timeupdate", this.onTimeUpdate);
        this.player.off?.("seeked", this.onTimeUpdate);
      }
      if (this.onMetadata) {
        this.player.off?.("loadedmetadata", this.onMetadata);
        this.player.off?.("ready", this.onMetadata);
      }
    } catch (_) {}
    this.onTimeUpdate = null;
    this.onMetadata = null;
  },

  refreshIndicator() {
    if (!this.indicator) return;
    const duration = this.effectiveDuration();
    if (!duration) {
      this.indicator.style.left = "0%";
      return;
    }
    const t = this.player?.currentTime ?? this.video?.currentTime ?? 0;
    const ratio = clamp(t / duration, 0, 1);
    this.indicator.style.left = `${(ratio * 100).toFixed(3)}%`;
  },

  effectiveDuration() {
    if (Number.isFinite(this.duration) && this.duration > 0) return this.duration;
    const d = this.player?.duration;
    return Number.isFinite(d) && d > 0 ? d : 0;
  },

  attachPointerSeek() {
    // Drag-to-seek with pointer events, with one-shot click as a special case.
    this.el.addEventListener("pointerdown", (event) => {
      // Ignore clicks on annotation markers — those are handled by
      // PandoraMoviePlayer's `[data-role=annotation-checkpoint]` delegation.
      if (event.target.closest("[data-role=annotation-checkpoint]")) return;
      // Left button only.
      if (event.button !== 0) return;

      const duration = this.effectiveDuration();
      if (!duration || !this.player) return;

      this.dragging = true;
      this.el.setPointerCapture?.(event.pointerId);
      this.seekFromEvent(event);

      this.onPointerMove = (e) => {
        if (!this.dragging) return;
        this.seekFromEvent(e);
      };
      this.onPointerUp = (e) => {
        if (!this.dragging) return;
        this.dragging = false;
        try {
          this.el.releasePointerCapture?.(e.pointerId);
        } catch (_) {}
        window.removeEventListener("pointermove", this.onPointerMove);
        window.removeEventListener("pointerup", this.onPointerUp);
        this.onPointerMove = null;
        this.onPointerUp = null;
      };

      window.addEventListener("pointermove", this.onPointerMove);
      window.addEventListener("pointerup", this.onPointerUp);

      event.preventDefault();
    });
  },

  seekFromEvent(event) {
    const duration = this.effectiveDuration();
    if (!duration || !this.player) return;
    const rect = this.img?.getBoundingClientRect() || this.el.getBoundingClientRect();
    const ratio = ratioFromPointer(rect, event.clientX);
    this.player.currentTime = ratio * duration;
    this.refreshIndicator();
  },

  // Left/Right arrow keys when the strip itself is focused = step ±1 % of
  // duration; Home/End jump to start/end. Plyr already handles its own
  // keyboard shortcuts (focused: true), so this only fires when the user
  // tabs onto the strip.
  attachKeyboardSeek() {
    this.el.tabIndex = 0;
    this.el.addEventListener("keydown", (event) => {
      const duration = this.effectiveDuration();
      if (!duration || !this.player) return;
      let nextRatio = null;
      switch (event.key) {
        case "ArrowLeft":
          nextRatio = clamp((this.player.currentTime - duration * 0.01) / duration, 0, 1);
          break;
        case "ArrowRight":
          nextRatio = clamp((this.player.currentTime + duration * 0.01) / duration, 0, 1);
          break;
        case "Home":
          nextRatio = 0;
          break;
        case "End":
          nextRatio = 1;
          break;
        default:
          return;
      }
      event.preventDefault();
      this.player.currentTime = nextRatio * duration;
      this.refreshIndicator();
    });
  },
};

export default PandoraTimelineStrip;
