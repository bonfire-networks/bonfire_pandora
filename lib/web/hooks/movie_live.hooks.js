/**
 * PandoraMoviePlayer
 *
 * Plyr-based player for the MovieLive editor (replaces the previous
 * VidstackHook that drove a bare `<video>` with custom controls).
 *
 * Why Plyr: it is already the player used in the feed preview
 * (`plyr_init.hooks.js`) and it is shipped as an extension dependency in
 * `bonfire_pandora/package.json`. Reusing it keeps the styling, fullscreen,
 * keyboard shortcuts and accessibility semantics consistent across the
 * Federated Archives flavour.
 *
 * Custom additions on top of Plyr:
 *   - Frame-step buttons (prev/next, fps from `data-fps` or default 25).
 *   - Mark IN / Mark OUT buttons that `pushEvent` to LiveView so the
 *     annotation form stays in sync with the player position.
 *   - Click handler on `[data-role=annotation-checkpoint]` badges so any
 *     annotation badge anywhere on the page seeks the player.
 *   - One-shot seek when arriving with `?in=&out=` query params.
 *   - Custom `pandora:movie-player:ready` window event so the TimelineStrip
 *     hook (Phase 4) can subscribe to Plyr events without coupling.
 */
import Plyr from "plyr";

const DEFAULT_FPS = 25;

function movieFps(rootEl) {
  const fps = parseFloat(rootEl?.dataset?.fps);
  return Number.isFinite(fps) && fps > 0 ? fps : DEFAULT_FPS;
}

function formatTime(s) {
  if (!Number.isFinite(s) || s < 0) return "00:00:00";
  const h = Math.floor(s / 3600);
  const m = Math.floor(s / 60) % 60;
  const sec = Math.floor(s) % 60;
  return [h, m, sec].map((n) => String(n).padStart(2, "0")).join(":");
}

function formatPlayerTime(s, fps) {
  if (!Number.isFinite(s) || s < 0) return "--:--:--:--";
  const rate = fps || DEFAULT_FPS;
  const h = Math.floor(s / 3600);
  const m = Math.floor(s / 60) % 60;
  const sec = Math.floor(s) % 60;
  const frameMax = Math.max(0, Math.round(rate) - 1);
  let ff = Math.floor((s - Math.floor(s)) * rate + 1e-6);
  if (ff > frameMax) ff = frameMax;
  return [h, m, sec, ff].map((n) => String(n).padStart(2, "0")).join(":");
}

function updateAnnotationFormBadge(which, seconds) {
  const badge = document.querySelector(
    which === "in"
      ? "#annotation-form-in, [data-role=annotation-form-in]"
      : "#annotation-form-out, [data-role=annotation-form-out]"
  );
  if (!badge) return;
  badge.dataset[which] = String(seconds);
  badge.textContent = `${which}: ${formatTime(seconds)}`;
}

function defaultControls() {
  return [
    "play-large",
    "play",
    "progress",
    "current-time",
    "duration",
    "mute",
    "volume",
    "settings",
    "fullscreen",
  ];
}

function safePlay(player) {
  try {
    const p = player.play();
    if (p && typeof p.catch === "function") p.catch(() => {});
  } catch (_) {}
}

const PandoraMoviePlayer = {
  mounted() {
    this.video = this.el.querySelector("video.player");
    if (!this.video) {
      console.warn("[PandoraMoviePlayer] no <video.player> inside hook root");
      return;
    }

    try {
      this.player = new Plyr(this.video, {
        controls: false,
        keyboard: { focused: true, global: false },
        seekTime: 5,
        clickToPlay: true,
        hideControls: false,
        tooltips: { controls: false, seek: false },
      });
    } catch (err) {
      console.warn("[PandoraMoviePlayer] Plyr init failed:", err);
      this.player = null;
    }

    if (this.player) {
      this.player.on("ready", () => {
        window.dispatchEvent(
          new CustomEvent("pandora:movie-player:ready", {
            detail: {
              hookId: this.el.id,
              player: this.player,
              video: this.video,
            },
          })
        );
        this.applySeekFromParams();
        this.setupPlayerControls();
      });
    }

    this.setupCustomButtons();
    this.setupBadgeClickDelegation();
  },

  destroyed() {
    if (this.badgeHandler) {
      document.removeEventListener("click", this.badgeHandler, true);
      this.badgeHandler = null;
    }
    window.dispatchEvent(
      new CustomEvent("pandora:movie-player:destroyed", {
        detail: { hookId: this.el.id },
      })
    );
    try {
      this.player?.destroy();
    } catch (_) {}
    this.player = null;
  },

  setupCustomButtons() {
    const inBtn = this.el.querySelector('[data-action="mark-in"]');
    const outBtn = this.el.querySelector('[data-action="mark-out"]');
    const prev = this.el.querySelector('[data-action="prev-frame"]');
    const next = this.el.querySelector('[data-action="next-frame"]');
    const currentTime = () =>
      this.player?.currentTime ?? this.video?.currentTime ?? 0;

    const pushMark = (event, which, seconds) => {
      updateAnnotationFormBadge(which, seconds);
      this.pushEvent(event, { timestamp: seconds });
    };

    if (inBtn) {
      inBtn.addEventListener("click", () => {
        pushMark("mark_in_timestamp", "in", currentTime());
      });
    }
    if (outBtn) {
      outBtn.addEventListener("click", () => {
        pushMark("mark_out_timestamp", "out", currentTime());
      });
    }
    if (prev) prev.addEventListener("click", () => this.stepFrame(-1));
    if (next) next.addEventListener("click", () => this.stepFrame(+1));
  },

  stepFrame(direction) {
    if (!this.player) return;
    const fps = parseFloat(this.el.dataset.fps) || DEFAULT_FPS;
    const dt = 1 / fps;
    if (!this.player.paused) this.player.pause();
    const duration = Number.isFinite(this.player.duration) ? this.player.duration : Infinity;
    const next = Math.max(0, Math.min(duration, (this.player.currentTime || 0) + direction * dt));
    this.player.currentTime = next;
  },

  setupBadgeClickDelegation() {
    // Event delegation: covers annotation badges rendered anywhere (player
    // controls, annotations list, threads), including dynamically inserted
    // ones (LiveView phx-update="append").
    this.badgeHandler = (event) => {
      const badge = event.target.closest("[data-role=annotation-checkpoint]");
      if (!badge) return;
      const tIn = parseFloat(badge.dataset.in);
      const tOut = parseFloat(badge.dataset.out);
      const target = Number.isFinite(tIn) ? tIn : Number.isFinite(tOut) ? tOut : NaN;
      if (!Number.isFinite(target) || !this.player) return;
      this.player.currentTime = target;
      safePlay(this.player);
    };
    document.addEventListener("click", this.badgeHandler, true);
  },

  setupPlayerControls() {
    const el = this.el;

    const playPauseBtn = el.querySelector('[data-action="play-pause"]');
    if (playPauseBtn) {
      playPauseBtn.addEventListener("click", () => this.player.togglePlay());
      const playIcon  = playPauseBtn.querySelector(".play-icon");
      const pauseIcon = playPauseBtn.querySelector(".pause-icon");
      const syncPlay = () => {
        const paused = this.player.paused;
        playIcon?.classList.toggle("hidden", !paused);
        pauseIcon?.classList.toggle("hidden", paused);
      };
      this.player.on("play",  syncPlay);
      this.player.on("pause", syncPlay);
      this.player.on("ended", syncPlay);
      syncPlay();
    }

    const muteBtn = el.querySelector('[data-action="toggle-mute"]');
    if (muteBtn) {
      muteBtn.addEventListener("click", () => {
        this.player.muted = !this.player.muted;
      });
      const unmutedIcon = muteBtn.querySelector(".unmuted-icon");
      const mutedIcon   = muteBtn.querySelector(".muted-icon");
      const syncMute = () => {
        const muted = this.player.muted || this.player.volume === 0;
        unmutedIcon?.classList.toggle("hidden", muted);
        mutedIcon?.classList.toggle("hidden", !muted);
      };
      this.player.on("volumechange", syncMute);
      syncMute();
    }

    const speedSelect = el.querySelector('[data-role="speed-select"]');
    if (speedSelect) {
      speedSelect.addEventListener("change", () => {
        this.player.speed = parseFloat(speedSelect.value);
      });
      this.player.on("ratechange", () => {
        speedSelect.value = String(this.player.speed);
      });
    }

    const fullscreenBtn = el.querySelector('[data-action="toggle-fullscreen"]');
    if (fullscreenBtn) {
      fullscreenBtn.addEventListener("click", () =>
        this.player.fullscreen.toggle()
      );
      const fsEnter = fullscreenBtn.querySelector(".fs-enter-icon");
      const fsExit  = fullscreenBtn.querySelector(".fs-exit-icon");
      const syncFs = () => {
        const isFs = this.player.fullscreen.active;
        fsEnter?.classList.toggle("hidden", isFs);
        fsExit?.classList.toggle("hidden", !isFs);
      };
      this.player.on("enterfullscreen", syncFs);
      this.player.on("exitfullscreen",  syncFs);
    }

    const timecode = el.querySelector('[data-role="player-timecode"]');
    if (timecode) {
      const fps = movieFps(el);
      const syncTimecode = () => {
        timecode.textContent =
          formatPlayerTime(this.player.currentTime, fps) +
          " / " +
          formatPlayerTime(this.player.duration, fps);
      };
      this.player.on("timeupdate", syncTimecode);
      this.player.on("loadedmetadata", syncTimecode);
      syncTimecode();
    }
  },

  applySeekFromParams() {
    const t = parseFloat(this.el.dataset.seekIn);
    if (!Number.isFinite(t) || !this.player) return;
    const doSeek = () => {
      this.player.currentTime = t;
      safePlay(this.player);
    };
    if (this.video && this.video.readyState >= 1) {
      doSeek();
    } else if (this.video) {
      this.video.addEventListener("loadedmetadata", doSeek, { once: true });
    }
  },
};

export default PandoraMoviePlayer;
