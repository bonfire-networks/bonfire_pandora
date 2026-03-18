/**
 * Inizializza Plyr su video con class="plyr" o data-plyr.
 * Plyr è importato dal bundle (npm). Usa MutationObserver per video inseriti dinamicamente (feed).
 */
import Plyr from "plyr";

const PlyrInit = {
  mounted() {
    this.players = [];
    const hook = this;
    const videos = this.el.querySelectorAll("video.plyr, video[data-plyr], video.pandora-video-preview");
    if (typeof window !== "undefined" && window.console) {
      console.log("[PlyrInit] mounted, videos found:", videos.length, "in", this.el);
    }
    this.initPlyrsIn(this.el);
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach((m) => {
        m.addedNodes.forEach((node) => {
          if (node.nodeType === 1) hook.initPlyrsIn(node);
        });
      });
    });
    this.observer.observe(this.el, { childList: true, subtree: true });
  },

  destroyed() {
    this.observer?.disconnect();
    this.players?.forEach((p) => {
      try {
        p.destroy();
      } catch (_) {}
    });
  },

  initPlyrsIn(container) {
    if (!container?.querySelectorAll) return;
    const hook = this;
    const videos = container.querySelectorAll("video.plyr, video[data-plyr], video.pandora-video-preview");
    videos.forEach((v) => {
      if (v.dataset.plyrInitialized === "true") return;
      v.dataset.plyrInitialized = "true";
      try {
        const player = new Plyr(v, {
          controls: ["play-large", "play", "progress", "current-time", "mute", "volume", "fullscreen"],
          hideControls: true,
        });
        hook.players = hook.players || [];
        hook.players.push(player);
        if (typeof window !== "undefined" && window.console) {
          console.log("[PlyrInit] Plyr initialized on video");
        }
      } catch (err) {
        console.warn("[PlyrInit] Failed to init Plyr on video:", err);
      }
    });
  },
};

export default PlyrInit;
