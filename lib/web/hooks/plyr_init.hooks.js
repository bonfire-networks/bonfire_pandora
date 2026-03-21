/**
 * Inizializza Plyr su video con class="plyr" o data-plyr o pandora-video-preview.
 * MutationObserver per video inseriti dinamicamente (feed).
 *
 * **Pandora preview** (`pandora-video-preview`): lazy `src`, poster 512p, segmento in/out.
 * Controlli senza progress; loop continuo su [in,out] via `timeupdate`; a fine segmento
 * (pause/ended del browser sul media fragment) si torna a `in`, si mostra icona **loop** sul
 * pulsante centrale; un nuovo play riparte da `in` (non oltre `out`).
 */
import Plyr from "plyr";

const LAZY_IO_ROOT_MARGIN = "240px";
const LAZY_IO_THRESHOLD = 0.01;

/** Salto prima di `out` durante la riproduzione (evita `ended` / pausa del browser). */
const LOOP_JUMP_EPS = 0.18;

/** Soglia più stretta: pausa manuale vicinissima alla fine = “fine segmento”. */
const AT_END_PAUSE_EPS = 0.06;

const LOOP_UI_CLASS = "pandora-segment-await-loop";
const STYLE_ID = "pandora-plyr-preview-segment-styles";

function injectPandoraPlyrPreviewStylesOnce() {
  if (typeof document === "undefined" || document.getElementById(STYLE_ID)) return;
  const el = document.createElement("style");
  el.id = STYLE_ID;
  el.textContent = `
    .${LOOP_UI_CLASS} .plyr__control--overlaid svg {
      display: none !important;
    }
    .${LOOP_UI_CLASS} .plyr__control--overlaid {
      align-items: center;
      justify-content: center;
    }
    .${LOOP_UI_CLASS} .plyr__control--overlaid::after {
      content: "↻";
      font-size: 1.85rem;
      line-height: 1;
      color: #fff;
      text-shadow: 0 1px 2px rgba(0,0,0,0.45);
      pointer-events: none;
    }
  `;
  document.head.appendChild(el);
}

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
 * Loop mentre in play; su ended / pausa a fine segmento → seek a in + classe UI loop.
 * Su play: rimuove UI e clamp così non si riparte oltre out.
 */
function attachPandoraSegmentLoop(player, tIn, tOut) {
  const media = player.media;
  const container = player.elements?.container;
  if (!container) return () => {};

  const clearAwaitLoopUi = () => container.classList.remove(LOOP_UI_CLASS);
  const setAwaitLoopUi = () => container.classList.add(LOOP_UI_CLASS);

  const onTimeUpdate = () => {
    if (media.paused) return;
    clearAwaitLoopUi();
    if (media.currentTime < tIn) {
      media.currentTime = tIn;
      return;
    }
    if (media.currentTime >= tOut - LOOP_JUMP_EPS) {
      media.currentTime = tIn;
    }
  };

  const onPlay = () => {
    clearAwaitLoopUi();
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
      setAwaitLoopUi();
    }
  };

  const onEnded = () => {
    media.currentTime = tIn;
    setAwaitLoopUi();
  };

  media.addEventListener("timeupdate", onTimeUpdate);
  media.addEventListener("play", onPlay);
  media.addEventListener("pause", onPause);
  media.addEventListener("ended", onEnded);

  return () => {
    clearAwaitLoopUi();
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
  return ["play-large", "play", "mute", "volume", "fullscreen"];
}

function createPlyrOnVideo(video, hook) {
  try {
    const isPandoraPreview = video.classList.contains("pandora-video-preview");
    const controls = isPandoraPreview ? pandoraPreviewControls() : defaultControls();

    const player = new Plyr(video, {
      controls,
      hideControls: true,
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
    injectPandoraPlyrPreviewStylesOnce();
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
