/**
 * Inizializza Plyr su video con class="plyr" o data-plyr o pandora-video-preview.
 * MutationObserver per video inseriti dinamicamente (feed).
 *
 * **Lazy src (Pandora preview):** i marker espandono `<video>` senza `src`, con
 * `data-pandora-video-src` e `poster` (frame 96p come embed Pandora). Il mp4 viene
 * assegnato solo quando il video entra in viewport (IntersectionObserver), per
 * ridurre banda nel feed. `preload="none"` resta sul markup.
 */
import Plyr from "plyr";

const LAZY_IO_ROOT_MARGIN = "240px";
const LAZY_IO_THRESHOLD = 0.01;

function createPlyrOnVideo(video, hook) {
  try {
    const player = new Plyr(video, {
      controls: ["play-large", "play", "progress", "current-time", "mute", "volume", "fullscreen"],
      hideControls: true,
    });
    hook.players = hook.players || [];
    hook.players.push(player);
  } catch (err) {
    console.warn("[PlyrInit] Failed to init Plyr on video:", err);
  }
}

function observeLazyPandoraVideo(video, hook) {
  if (video.dataset.pandoraLazyObserved === "true") return;
  video.dataset.pandoraLazyObserved = "true";

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const v = entry.target;
        const src = v.dataset.pandoraVideoSrc;
        if (!src) {
          io.unobserve(v);
          return;
        }
        delete v.dataset.pandoraVideoSrc;
        io.unobserve(v);
        v.src = src;
        createPlyrOnVideo(v, hook);
      });
    },
    { root: null, rootMargin: LAZY_IO_ROOT_MARGIN, threshold: LAZY_IO_THRESHOLD }
  );
  io.observe(video);
}

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

      const lazySrc = v.dataset.pandoraVideoSrc;
      if (lazySrc && !v.getAttribute("src")) {
        v.dataset.plyrInitialized = "true";
        observeLazyPandoraVideo(v, hook);
        return;
      }

      v.dataset.plyrInitialized = "true";
      createPlyrOnVideo(v, hook);
    });
  },
};

export default PlyrInit;
