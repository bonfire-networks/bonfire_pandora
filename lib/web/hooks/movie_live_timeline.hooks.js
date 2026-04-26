/**
 * PandoraTimelineStrip
 *
 * Compact strip (16p, always visible): keyframe tiles compressed to container
 * width — rough seek reference. For movies > 60 min all tiles are stitched
 * proportionally via CSS background-size.
 *
 * Large timeline (toggled by expand button): vertically-stacked strip rows,
 * one per 64p tile (1500×64 px = 60 s at 25 px/s). Each row is a pre-composed
 * filmstrip covering 60 seconds; the rows are loaded lazily as the user scrolls.
 * Clicking any row seeks to the corresponding position. A thin vertical
 * playhead line (--row-position CSS var) tracks the current time within the
 * highlighted row.
 */

const POSITION_ID         = "timeline_strip_position";
const POSITION_64_ID      = "timeline_strip_position_64";
const SECONDS_PER_TILE    = 3600; // 16p small tiles: 1 hour each
const LARGE_SECS_PER_TILE = 60;   // 64p large tiles: 60 seconds each (1500 px at 25 px/s)

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

function formatTimecode(seconds) {
  const s = Math.floor(seconds) % 60;
  const m = Math.floor(seconds / 60) % 60;
  const h = Math.floor(seconds / 3600);
  return [h, m, s].map((n) => String(n).padStart(2, "0")).join(":");
}

function debounce(fn, delay) {
  let timer = null;
  return (...args) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}

const PandoraTimelineStrip = {
  mounted() {
    this.indicator         = this.el.querySelector(`#${POSITION_ID}`);
    this.img               = this.el.querySelector("img.timeline-strip-img");
    this.duration          = parseFloat(this.el.dataset.duration) || NaN;
    this.targetPlayerId    = this.el.dataset.targetPlayer || "movie_player_root";
    this.fallbackSrc       = this.el.dataset.fallbackSrc || "";
    this.frameUrlTemplate  = this.el.dataset.frameUrlTemplate || "";
    this.tileUrlTemplate16 = this.el.dataset.tileUrlTemplate16 || "";
    this.tileUrlTemplate64 = this.el.dataset.tileUrlTemplate64 || "";
    this.expandedStripId   = this.el.dataset.expandedStripId || "timeline_strip_expanded";
    this.fallbackUsed = false;

    this._tilesBuilt           = { compact: false, expanded: false };
    this.isExpanded            = false;
    this._userScrolling        = false;
    this._scrollTimeout        = null;
    this._framePreviewAttached = false;
    this._expandedSeekAttached = false;
    this._largeTileRows        = [];
    this._lastFrameIndex       = -1;
    this._currentFrameEl       = null;

    this.player           = null;
    this.video            = null;
    this.dragging         = false;
    this.expandBtn        = null;
    this.expandedEl       = null;
    this.expandedPosition = null;
    this.framePreviewEl   = null;
    this.framePreviewImg  = null;
    this.frameTimecode    = null;

    this.attachImageFallback();
    this.attachPointerSeek();
    this.attachPlayerListeners();
    this.attachKeyboardSeek();
    this.attachExpandToggle();

    console.debug("[timeline] mounted", {
      tileUrl64: this.tileUrlTemplate64 ? "ok" : "EMPTY",
      tileUrl16: this.tileUrlTemplate16 ? "ok" : "EMPTY",
      frameUrl:  this.frameUrlTemplate  ? "ok" : "EMPTY",
      duration:  this.duration,
      expandedEl: !!document.getElementById(this.expandedStripId),
    });

    if (this.effectiveDuration() > SECONDS_PER_TILE) this.rebuildCompactTiles();
  },

  updated() {
    if (this.expandedEl) {
      this.expandedEl.classList.toggle("hidden", !this.isExpanded);
    }
    if (this.expandBtn) {
      this.expandBtn.setAttribute("aria-expanded", String(this.isExpanded));
    }

    const newDuration = parseFloat(this.el.dataset.duration) || NaN;
    if (!Number.isNaN(newDuration)) this.duration = newDuration;

    this.frameUrlTemplate  = this.el.dataset.frameUrlTemplate  || this.frameUrlTemplate;
    this.tileUrlTemplate16 = this.el.dataset.tileUrlTemplate16 || this.tileUrlTemplate16;
    this.tileUrlTemplate64 = this.el.dataset.tileUrlTemplate64 || this.tileUrlTemplate64;

    if (this.isExpanded) {
      this._framePreviewAttached = false;
      this._expandedSeekAttached = false;
      this.attachFramePreview();
      this.attachExpandedPointerSeek();
    }
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
    if (this._scrollTimeout) clearTimeout(this._scrollTimeout);
  },

  // ─── compact strip image fallback ─────────────────────────────────────────

  attachImageFallback() {
    if (!this.img) return;
    this.img.addEventListener("error", this.onImageError.bind(this));
    this.img.addEventListener("load",  this.onImageLoad.bind(this));
    if (this.img.complete) {
      if (this.img.naturalWidth === 0) this.onImageError();
      else this.onImageLoad();
    }
  },

  onImageLoad() {
    if (this.img && this.img.naturalWidth === 0) { this.onImageError(); return; }
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

  // ─── player binding ────────────────────────────────────────────────────────

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
      this.video  = null;
    };
    window.addEventListener("pandora:movie-player:ready",     this.onMoviePlayerReady);
    window.addEventListener("pandora:movie-player:destroyed", this.onMoviePlayerDestroyed);
  },

  bindPlayer(player, video) {
    this.player = player;
    this.video  = video;
    this.detachPlayerEvents();
    this.attachPlayerEvents();
    this.refreshIndicator();
  },

  attachPlayerEvents() {
    if (!this.player) return;

    this.onTimeUpdate = () => this.refreshIndicator();
    this.onMetadata   = () => {
      if (!Number.isFinite(this.duration) || this.duration <= 0) {
        const d = this.player?.duration;
        if (Number.isFinite(d) && d > 0) {
          this.duration = d;
          this.el.dataset.duration = String(d);
        }
      }
      this.refreshIndicator();
      if (this.effectiveDuration() > SECONDS_PER_TILE) this.rebuildCompactTiles();
      if (this.isExpanded && !this._tilesBuilt.expanded) this.buildLargeTimeline();
    };

    this.player.on("timeupdate",     this.onTimeUpdate);
    this.player.on("seeked",         this.onTimeUpdate);
    this.player.on("loadedmetadata", this.onMetadata);
    this.player.on("ready",          this.onMetadata);

    this.refreshIndicator();
  },

  detachPlayerEvents() {
    if (!this.player) return;
    try {
      this.player.off?.("timeupdate",     this.onTimeUpdate);
      this.player.off?.("seeked",         this.onTimeUpdate);
      this.player.off?.("loadedmetadata", this.onMetadata);
      this.player.off?.("ready",          this.onMetadata);
    } catch (_) {}
    this.onTimeUpdate = null;
    this.onMetadata   = null;
  },

  // ─── position indicators ───────────────────────────────────────────────────

  effectiveDuration() {
    if (Number.isFinite(this.duration) && this.duration > 0) return this.duration;
    const d = this.player?.duration;
    return Number.isFinite(d) && d > 0 ? d : 0;
  },

  refreshIndicator() {
    const duration = this.effectiveDuration();
    const t = this.player?.currentTime ?? this.video?.currentTime ?? 0;
    const ratio = duration ? clamp(t / duration, 0, 1) : 0;

    if (this.indicator) this.indicator.style.left = `${(ratio * 100).toFixed(3)}%`;

    if (this._tilesBuilt.expanded && this.expandedEl) {
      this.refreshLargeIndicator(t);
    }
  },

  refreshLargeIndicator(t) {
    const rows      = this._largeTileRows;
    const tileIndex = Math.floor(t / LARGE_SECS_PER_TILE);
    const row       = rows && rows[tileIndex];

    if (row) {
      const tileDuration = parseFloat(row.dataset.tileDuration) || LARGE_SECS_PER_TILE;
      const offsetInTile = t - tileIndex * LARGE_SECS_PER_TILE;
      const pct = clamp(offsetInTile / tileDuration * 100, 0, 100).toFixed(3);
      row.style.setProperty("--row-position", `${pct}%`);
    }

    if (tileIndex === this._lastFrameIndex) return;

    if (this._currentFrameEl) {
      this._currentFrameEl.classList.remove("is-current");
    }
    if (row) {
      row.classList.add("is-current");
      this._currentFrameEl = row;
      this.autoScrollLargeTimeline(row);
    }
    this._lastFrameIndex = tileIndex;
  },

  autoScrollLargeTimeline(rowEl) {
    if (!this._userScrolling && rowEl) {
      rowEl.scrollIntoView({ block: "nearest", behavior: "smooth" });
    }
  },

  // ─── compact strip: multi-tile rebuild for long videos ────────────────────

  rebuildCompactTiles() {
    if (this._tilesBuilt.compact || !this.img) return;
    const duration = this.effectiveDuration();
    if (!duration || !this.tileUrlTemplate16) return;
    this._tilesBuilt.compact = true;

    const totalTiles = Math.ceil(duration / SECONDS_PER_TILE);
    const parts = [];
    for (let i = 0; i < totalTiles; i++) {
      const url = this.tileUrlTemplate16.replace("{i}", String(i));
      const pct = ((i / totalTiles) * 100).toFixed(4);
      const w   = (100 / totalTiles).toFixed(4);
      parts.push(`url('${url}') ${pct}% / ${w}% 100%`);
    }

    Object.assign(this.img.style, {
      backgroundImage: parts.join(", "),
      backgroundRepeat: "no-repeat",
      backgroundSize: `${(100 / totalTiles).toFixed(4)}% 100%`,
      width: "100%",
      height: "100%",
      objectFit: "fill",
    });
    this.img.src = "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==";
  },

  // ─── compact strip seek ────────────────────────────────────────────────────

  attachPointerSeek() {
    this.el.addEventListener("pointerdown", (event) => {
      if (event.target.closest("[data-role=annotation-checkpoint]")) return;
      if (event.button !== 0) return;
      const duration = this.effectiveDuration();
      if (!duration || !this.player) return;

      this.dragging = true;
      this.el.setPointerCapture?.(event.pointerId);
      this.seekFromRect(this.img?.getBoundingClientRect() || this.el.getBoundingClientRect(), event.clientX);

      this.onPointerMove = (e) => {
        if (!this.dragging) return;
        this.seekFromRect(this.img?.getBoundingClientRect() || this.el.getBoundingClientRect(), e.clientX);
      };
      this.onPointerUp = (e) => {
        if (!this.dragging) return;
        this.dragging = false;
        try { this.el.releasePointerCapture?.(e.pointerId); } catch (_) {}
        window.removeEventListener("pointermove", this.onPointerMove);
        window.removeEventListener("pointerup",   this.onPointerUp);
        this.onPointerMove = null;
        this.onPointerUp   = null;
      };
      window.addEventListener("pointermove", this.onPointerMove);
      window.addEventListener("pointerup",   this.onPointerUp);
      event.preventDefault();
    });
  },

  seekFromRect(rect, clientX) {
    const duration = this.effectiveDuration();
    if (!duration || !this.player) return;
    this.player.currentTime = ratioFromPointer(rect, clientX) * duration;
    this.refreshIndicator();
  },

  // ─── keyboard seek (compact strip) ────────────────────────────────────────

  attachKeyboardSeek() {
    this.el.tabIndex = 0;
    this.el.addEventListener("keydown", (event) => {
      const duration = this.effectiveDuration();
      if (!duration || !this.player) return;
      let nextRatio = null;
      switch (event.key) {
        case "ArrowLeft":  nextRatio = clamp((this.player.currentTime - duration * 0.01) / duration, 0, 1); break;
        case "ArrowRight": nextRatio = clamp((this.player.currentTime + duration * 0.01) / duration, 0, 1); break;
        case "Home": nextRatio = 0; break;
        case "End":  nextRatio = 1; break;
        default: return;
      }
      event.preventDefault();
      this.player.currentTime = nextRatio * duration;
      this.refreshIndicator();
    });
  },

  // ─── expand / collapse ─────────────────────────────────────────────────────

  attachExpandToggle() {
    this.expandBtn  = document.getElementById("timeline_expand_btn");
    this.expandedEl = document.getElementById(this.expandedStripId);
    if (!this.expandBtn || !this.expandedEl) {
      console.warn("[timeline] attachExpandToggle: missing elements", {
        expandBtn: !!this.expandBtn,
        expandedEl: !!this.expandedEl,
        expandedStripId: this.expandedStripId,
      });
      return;
    }

    this.expandedPosition = this.expandedEl.querySelector(`#${POSITION_64_ID}`);
    this.framePreviewEl   = this.expandedEl.querySelector("#timeline_frame_preview");
    if (this.framePreviewEl) {
      this.framePreviewImg = this.framePreviewEl.querySelector("img.timeline-frame-img");
      this.frameTimecode   = this.framePreviewEl.querySelector(".timeline-frame-timecode");
    }

    this.expandBtn.addEventListener("click", () => {
      this.isExpanded = !this.isExpanded;
      this.expandedEl.classList.toggle("hidden", !this.isExpanded);
      this.expandBtn.setAttribute("aria-expanded", String(this.isExpanded));
      this.expandBtn.title = this.isExpanded ? "Collapse timeline" : "Expand timeline";

      if (this.isExpanded) {
        this.buildLargeTimeline();
        if (!this._tilesBuilt.expanded) {
          setTimeout(() => { if (!this._tilesBuilt.expanded) this.buildLargeTimeline(); }, 800);
          setTimeout(() => { if (!this._tilesBuilt.expanded) this.buildLargeTimeline(); }, 2500);
        }
        this.refreshIndicator();
        this.attachFramePreview();
        this.attachExpandedPointerSeek();
      }
    });
  },

  // ─── large timeline: stacked 64p strip rows ───────────────────────────────

  buildLargeTimeline() {
    const duration = this.effectiveDuration();
    console.debug("[timeline] buildLargeTimeline", {
      duration,
      tileUrl64: this.tileUrlTemplate64 ? this.tileUrlTemplate64.slice(0, 60) + "…" : "EMPTY",
      expandedEl: !!this.expandedEl,
      alreadyBuilt: this._tilesBuilt.expanded,
    });
    if (!duration || !this.tileUrlTemplate64 || !this.expandedEl) {
      console.warn("[timeline] buildLargeTimeline: skipped",
        "duration=" + duration,
        "tileUrl64=" + (this.tileUrlTemplate64 ? "ok" : "EMPTY"),
        "expandedEl=" + !!this.expandedEl);
      return;
    }
    if (this._tilesBuilt.expanded) return;

    this._lastFrameIndex = -1;
    this._currentFrameEl = null;

    const inner     = document.createElement("div");
    inner.className = "timeline-large-inner";
    const totalTiles = Math.ceil(duration / LARGE_SECS_PER_TILE);

    for (let i = 0; i < totalTiles; i++) {
      const tileStart    = i * LARGE_SECS_PER_TILE;
      const tileDuration = Math.min(LARGE_SECS_PER_TILE, duration - tileStart);
      const url          = this.tileUrlTemplate64.replace("{i}", String(i));

      const row = document.createElement("div");
      row.className = "timeline-large-row";
      row.dataset.tileIndex    = String(i);
      row.dataset.tileStart    = String(tileStart);
      row.dataset.tileDuration = String(tileDuration);

      const img = document.createElement("img");
      img.className = "timeline-large-tile";
      img.src       = url;
      img.loading   = "lazy";
      img.draggable = false;
      img.alt       = "";

      if (tileDuration < LARGE_SECS_PER_TILE) {
        img.style.width = `${(tileDuration / LARGE_SECS_PER_TILE * 100).toFixed(4)}%`;
      }

      row.appendChild(img);
      inner.appendChild(row);
    }

    this._largeTileRows = Array.from(inner.querySelectorAll("div.timeline-large-row"));

    const origIndicator = this.expandedEl.querySelector(`#${POSITION_64_ID}`);
    if (origIndicator) origIndicator.style.display = "none";

    this.expandedEl.querySelector(".timeline-large-inner")?.remove();
    this.expandedEl.prepend(inner);

    this.expandedEl.addEventListener("scroll", () => {
      this._userScrolling = true;
      if (this._scrollTimeout) clearTimeout(this._scrollTimeout);
      this._scrollTimeout = setTimeout(() => { this._userScrolling = false; }, 1200);
    }, { passive: true });

    this._tilesBuilt.expanded = true;
  },

  // ─── large timeline: seek on tile row click ───────────────────────────────

  attachExpandedPointerSeek() {
    if (this._expandedSeekAttached || !this.expandedEl) return;
    this._expandedSeekAttached = true;

    this.expandedEl.addEventListener("click", (event) => {
      const rowEl = event.target.closest("div.timeline-large-row");
      if (!rowEl || !this.player) return;

      const tileStart    = parseFloat(rowEl.dataset.tileStart)    || 0;
      const tileDuration = parseFloat(rowEl.dataset.tileDuration) || LARGE_SECS_PER_TILE;
      const rowRect      = rowEl.getBoundingClientRect();
      const ratio        = clamp((event.clientX - rowRect.left) / rowRect.width, 0, 1);

      this.player.currentTime = tileStart + ratio * tileDuration;
      this.refreshIndicator();
    });
  },

  // ─── frame preview tooltip ────────────────────────────────────────────────

  attachFramePreview() {
    if (this._framePreviewAttached || !this.expandedEl || !this.framePreviewEl) return;
    if (!this.frameUrlTemplate) return;
    this._framePreviewAttached = true;

    const debouncedLoad = debounce((t) => {
      const url = this.frameUrlTemplate.replace("{t}", t.toFixed(3));
      if (this.framePreviewImg && this.framePreviewImg.src !== url) {
        this.framePreviewImg.src = url;
      }
    }, 80);

    this.expandedEl.addEventListener("pointermove", (event) => {
      const rowEl = event.target.closest("div.timeline-large-row");
      if (!rowEl) {
        this.framePreviewEl.classList.add("hidden");
        return;
      }
      const tileStart    = parseFloat(rowEl.dataset.tileStart)    || 0;
      const tileDuration = parseFloat(rowEl.dataset.tileDuration) || LARGE_SECS_PER_TILE;
      const rowRect      = rowEl.getBoundingClientRect();
      const ratio        = clamp((event.clientX - rowRect.left) / rowRect.width, 0, 1);
      const t            = tileStart + ratio * tileDuration;

      if (this.frameTimecode) this.frameTimecode.textContent = formatTimecode(t);

      const previewW = this.framePreviewEl.offsetWidth || 168;
      let left = event.clientX - previewW / 2;
      left = clamp(left, 8, window.innerWidth - previewW - 8);
      this.framePreviewEl.style.left = `${left}px`;
      this.framePreviewEl.style.top  = `${rowRect.top - this.framePreviewEl.offsetHeight - 8}px`;
      this.framePreviewEl.classList.remove("hidden");

      debouncedLoad(t);
    });

    this.expandedEl.addEventListener("pointerleave", () => {
      this.framePreviewEl.classList.add("hidden");
    });
  },
};

export default PandoraTimelineStrip;
