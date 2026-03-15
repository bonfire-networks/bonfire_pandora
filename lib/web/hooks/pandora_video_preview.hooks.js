/**
 * Pandora video preview: show poster image first, load video on click.
 * Uses document-level delegation so it works regardless of DOM structure.
 */
const handlePandoraVideoClick = (e) => {
  const placeholder = e.target.closest(".pandora-video-preview") || e.target.closest("[data-video-src]");
  if (!placeholder || placeholder.dataset.expanded === "true") return;

  e.preventDefault();
  e.stopPropagation();

  const videoSrc = placeholder.dataset.videoSrc;
  const movieUrl = placeholder.dataset.movieUrl;
  if (!videoSrc) return;

  placeholder.dataset.expanded = "true";

  if (placeholder.tagName === "VIDEO") {
    placeholder.src = videoSrc;
    placeholder.muted = true;
    placeholder.loop = true;
    placeholder.autoplay = true;
    placeholder.controls = true;
    placeholder.removeAttribute("poster");
    placeholder.play().catch(() => {});

    const link = document.createElement("a");
    link.href = movieUrl;
    link.textContent = "View full movie";
    link.className = "text-sm link link-hover mt-1 block";
    placeholder.parentNode.insertBefore(link, placeholder.nextSibling);
  } else {
    const video = document.createElement("video");
    video.src = videoSrc;
    video.muted = true;
    video.loop = true;
    video.autoplay = true;
    video.playsInline = true;
    video.width = 320;
    video.height = 180;
    video.controls = true;
    video.className = "rounded";

    const link = document.createElement("a");
    link.href = movieUrl;
    link.textContent = "View full movie";
    link.className = "text-sm link link-hover mt-1 block";

    const wrapper = document.createElement("div");
    wrapper.className = "flex flex-col";
    wrapper.appendChild(video);
    wrapper.appendChild(link);

    placeholder.innerHTML = "";
    placeholder.appendChild(wrapper);

    video.play().catch(() => {});
  }
};

let listenerCount = 0;

let PandoraVideoPreview = {
  mounted() {
    if (listenerCount === 0) {
      document.addEventListener("click", handlePandoraVideoClick, true);
    }
    listenerCount++;
  },

  destroyed() {
    listenerCount--;
    if (listenerCount <= 0) {
      listenerCount = 0;
      document.removeEventListener("click", handlePandoraVideoClick, true);
    }
  }
};

export default PandoraVideoPreview;
