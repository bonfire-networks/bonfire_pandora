/**
 * Inizializza Plyr su video con class="plyr" o data-plyr o pandora-video-preview.
 * MutationObserver per video inseriti dinamicamente (feed).
 *
 * **Pandora preview** (`pandora-video-preview`): lazy `src`, poster 512p, segmento in/out.
 * Nessun play centrale (`play-large`); solo play in barra + volume + fullscreen. `clickToPlay`
 * sul video. In play, il tempo torna a `in` poco prima di `out` (loop continuo del segmento).
 * Su pause/ended a fine segmento si fa seek a `in` per il play successivo (nessuna icona loop in UI).
 */
import Plyr from "plyr";

const LAZY_IO_ROOT_MARGIN = "240px";
const LAZY_IO_THRESHOLD = 0.01;

/** Salto prima di `out` durante la riproduzione (evita `ended` / pausa del browser). */
const LOOP_JUMP_EPS = 0.18;

/** Soglia più stretta: pausa manuale vicinissima alla fine = “fine segmento”. */
const AT_END_PAUSE_EPS = 0.06;

function parseSegmentBounds(video) {
  const tIn = parseFloat(video.dataset.pandoraIn);
  const tOut = parseFloat(video.dataset.pandoraOut);
  if (!Number.isFinite(tIn) || !Number.isFinite(tOut) || tOut <= tIn) {
    return null;
  }
  return { tIn, tOut };
}

function atOrPastSegmentEnd(media, tOut) {
  return media.ended || media.currentTime >= tOut - AT_END_PAUSE_EPS || media.currentTime > tOut;
}

/**
 * Loop del segmento [in,out] in riproduzione (seek a `in` prima di `out`).
 * Su pause/ended a fine segmento: seek a `in` così il prossimo play riparte dal punto giusto.
 */
function attachPandoraSegmentLoop(player, tIn, tOut) {
  const media = player.media;
  if (!media) return () => {};

  const onTimeUpdate = () => {
    if (media.paused) return;
    if (media.currentTime < tIn) {
      media.currentTime = tIn;
      return;
    }
    if (media.currentTime >= tOut - LOOP_JUMP_EPS) {
      media.currentTime = tIn;
    }
  };

  const onPlay = () => {
    if (media.currentTime >= tOut - AT_END_PAUSE_EPS || media.currentTime > tOut || media.ended) {
      media.currentTime = tIn;
    }
    if (media.currentTime < tIn) {
      media.currentTime = tIn;
    }
  };

  const onPause = () => {
    if (atOrPastSegmentEnd(media, tOut)) {
      media.currentTime = tIn;
    }
  };

  const onEnded = () => {
    media.currentTime = tIn;
  };

  media.addEventListener("timeupdate", onTimeUpdate);
  media.addEventListener("play", onPlay);
  media.addEventListener("pause", onPause);
  media.addEventListener("ended", onEnded);

  return () => {
    media.removeEventListener("timeupdate", onTimeUpdate);
    media.removeEventListener("play", onPlay);
    media.removeEventListener("pause", onPause);
    media.removeEventListener("ended", onEnded);
  };
}

function defaultControls() {
  return ["play-large", "play", "progress", "current-time", "mute", "volume", "fullscreen"];
}

function pandoraPreviewControls() {
  return ["play", "mute", "volume", "fullscreen"];
}

function createPlyrOnVideo(video, hook) {
  try {
    const isPandoraPreview = video.classList.contains("pandora-video-preview");
    const controls = isPandoraPreview ? pandoraPreviewControls() : defaultControls();

    const player = new Plyr(video, {
      controls,
      hideControls: true,
      clickToPlay: true,
    });

    let cleanup = null;
    if (isPandoraPreview) {
      const bounds = parseSegmentBounds(video);
      if (bounds) {
        cleanup = attachPandoraSegmentLoop(player, bounds.tIn, bounds.tOut);
      }
    }

    hook.players = hook.players || [];
    hook.players.push({ player, cleanup });
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
    this.players?.forEach((entry) => {
      try {
        entry.cleanup?.();
      } catch (_) {}
      try {
        entry.player?.destroy();
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
