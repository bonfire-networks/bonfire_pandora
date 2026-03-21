/**
 * Inizializza Plyr su video con class="plyr" o data-plyr o pandora-video-preview.
 * MutationObserver per video inseriti dinamicamente (feed).
 *
 * **Thumb / primo frame (DISABILITATO per debug freeze al play):** la logica precedente
 * usava IntersectionObserver + preload metadata + load() + currentTime=0 come copertina.
 * È stata rimossa così il `<video>` resta solo con `preload="none"` dal server e Plyr
 * gestisce tutto. Ripristinare da git se serve di nuovo la copertina.
 */
import Plyr from "plyr";

const PlyrInit = {
  mounted() {
    this.players = [];
    this.initPlyrsIn(this.el);
    const hook = this;
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
      } catch (err) {
        console.warn("[PlyrInit] Failed to init Plyr on video:", err);
      }
    });
  },
};

export default PlyrInit;
