/**
 * Inizializza Plyr su video con class="plyr" o data-plyr.
 * Carica Plyr da CDN al primo utilizzo. Usa MutationObserver per video inseriti dinamicamente (feed).
 */
const PLYR_VERSION = "3.7.8";
const PLYR_CSS = `https://cdn.plyr.io/${PLYR_VERSION}/plyr.css`;
const PLYR_JS = `https://cdn.plyr.io/${PLYR_VERSION}/plyr.polyfilled.js`;

let plyrLoadPromise = null;

function loadPlyr() {
  if (window.Plyr) return Promise.resolve(window.Plyr);
  if (plyrLoadPromise) return plyrLoadPromise;

  plyrLoadPromise = new Promise((resolve, reject) => {
    if (document.querySelector('link[href="' + PLYR_CSS + '"]')) {
      if (window.Plyr) return resolve(window.Plyr);
      const check = setInterval(() => {
        if (window.Plyr) {
          clearInterval(check);
          resolve(window.Plyr);
        }
      }, 50);
      return;
    }

    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = PLYR_CSS;
    document.head.appendChild(link);

    const script = document.createElement("script");
    script.src = PLYR_JS;
    script.onload = () => resolve(window.Plyr);
    script.onerror = () => reject(new Error("Plyr failed to load"));
    document.head.appendChild(script);
  });

  return plyrLoadPromise;
}

const PlyrInit = {
  mounted() {
    this.players = [];
    const hook = this;
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
      loadPlyr()
        .then((Plyr) => {
          const player = new Plyr(v, {
            controls: ["play-large", "play", "progress", "current-time", "mute", "volume", "fullscreen"],
            hideControls: true,
          });
          hook.players = hook.players || [];
          hook.players.push(player);
        })
        .catch(() => {});
    });
  },
};

export default PlyrInit;
