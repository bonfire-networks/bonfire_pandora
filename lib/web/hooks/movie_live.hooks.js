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
        controls: defaultControls(),
        keyboard: { focused: true, global: false },
        seekTime: 5,
        clickToPlay: true,
        hideControls: false,
        tooltips: { controls: true, seek: true },
      });
    } catch (err) {
      console.warn("[PandoraMoviePlayer] Plyr init failed:", err);
      return;
    }

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
    });

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

    if (inBtn) {
      inBtn.addEventListener("click", () => {
        const t = this.player?.currentTime ?? 0;
        this.pushEvent("mark_in_timestamp", { timestamp: t });
      });
    }
    if (outBtn) {
      outBtn.addEventListener("click", () => {
        const t = this.player?.currentTime ?? 0;
        this.pushEvent("mark_out_timestamp", { timestamp: t });
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
