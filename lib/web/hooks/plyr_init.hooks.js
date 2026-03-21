/**
 * Inizializza Plyr su video con class="plyr" o data-plyr.
 * Import statico da npm. MutationObserver per video inseriti dinamicamente (feed).
 *
 * Per `video.pandora-video-preview`: niente poster da Pandora; quando il clip è vicino al
 * viewport si passa a preload=metadata e (se `PANDORA_CLIP_PREVIEW_METADATA_ONLY_NO_SEEK` è false)
 * seek a 0 + pausa per il primo frame. Flag true = solo metadata, test freeze al play.
 */
import Plyr from "plyr";

/**
 * A/B: when true, only preload metadata near viewport — no currentTime=0 / pause / seeked dance.
 * Use to test if play freeze is tied to paintFrameAtClipStart. Set back to false after investigation.
 */
const PANDORA_CLIP_PREVIEW_METADATA_ONLY_NO_SEEK = true;

/** @param {HTMLVideoElement} video */
function loadPandoraClipFirstFrame(video) {
  if (video.dataset.pandoraClipFirstFrameDone === "true") return;

  const finish = () => {
    video.dataset.pandoraClipFirstFrameDone = "true";
  };

  const paintFrameAtClipStart = () => {
    try {
      video.pause();
      const onSeeked = () => {
        video.removeEventListener("seeked", onSeeked);
        video.pause();
        finish();
      };
      video.addEventListener("seeked", onSeeked, { once: true });
      // Clip URL: timeline 0 == frame at annotation `in`.
      video.currentTime = 0;
      requestAnimationFrame(() => {
        if (video.dataset.pandoraClipFirstFrameDone === "true") return;
        if (video.readyState >= 2) {
          video.removeEventListener("seeked", onSeeked);
          video.pause();
          finish();
        }
      });
    } catch (_) {
      finish();
    }
  };

  const afterMetadataLoaded = () => {
    if (PANDORA_CLIP_PREVIEW_METADATA_ONLY_NO_SEEK) {
      finish();
    } else {
      paintFrameAtClipStart();
    }
  };

  if (video.readyState >= 2) {
    afterMetadataLoaded();
    return;
  }

  video.preload = "metadata";
  try {
    video.load();
  } catch (_) {}

  const onLoaded = () => {
    video.removeEventListener("loadeddata", onLoaded);
    afterMetadataLoaded();
  };
  video.addEventListener("loadeddata", onLoaded, { once: true });
  video.addEventListener(
    "error",
    () => {
      video.removeEventListener("loadeddata", onLoaded);
      finish();
    },
    { once: true }
  );
}

function ensurePandoraPreviewFirstFrameObserver(hook, video) {
  if (!(video instanceof HTMLVideoElement)) return;
  if (!video.classList.contains("pandora-video-preview")) return;
  if (video.dataset.pandoraClipFirstFrameObserved === "true") return;
  video.dataset.pandoraClipFirstFrameObserved = "true";

  hook.pandoraPreviewIo ||= new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const v = entry.target;
        hook.pandoraPreviewIo.unobserve(v);
        loadPandoraClipFirstFrame(v);
      });
    },
    { root: null, rootMargin: "160px", threshold: 0.01 }
  );

  hook.pandoraPreviewIo.observe(video);
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
    this.pandoraPreviewIo?.disconnect();
    this.pandoraPreviewIo = null;
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
      ensurePandoraPreviewFirstFrameObserver(hook, v);
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
