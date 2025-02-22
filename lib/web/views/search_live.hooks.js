let InfiniteScroll = {
  mounted() {
    this.initialize();
  },

  initialize() {
    this.pending = false;
    this.containerType = this.el.dataset.type; // "results" or "filter"
    
    if (this.containerType === "filter") {
      this.setupFilterSentinel();
    } else {
      this.setupResultsSentinel();
    }
  },

  setupFilterSentinel() {
    // Create sentinel for filter lists
    this.sentinel = document.createElement('div');
    this.sentinel.classList.add('loading-sentinel');
    this.sentinel.setAttribute('phx-update', 'ignore');
    this.sentinel.style.cssText = `
      height: 20px;
      width: 100%;
      padding: 0;
      margin: 0;
    `;

    const targetContainer = this.el.querySelector('ul.menu');
    if (targetContainer) {
      targetContainer.appendChild(this.sentinel);
    }

    this.setupObserver();
  },

  setupResultsSentinel() {
    // Use existing sentinel for search results
    this.sentinel = document.getElementById('search-results-sentinel');
    if (this.sentinel) {
      this.setupObserver();
    }
  },

  setupObserver() {
    if (!this.sentinel) return;

    this.observer = new IntersectionObserver(
      (entries) => this.handleIntersection(entries),
      {
        root: null,
        threshold: 0,
        rootMargin: "20px 0px 0px 0px"
      }
    );
    
    this.observer.observe(this.sentinel);
  },

  handleIntersection(entries) {
    const entry = entries[0];
    if (!entry.isIntersecting || this.pending || this.el.dataset.loading === "true") {
      return;
    }

    this.pending = true;
    const eventName = this.containerType === "filter" 
      ? `load_more_${this.el.id.replace('-container', '')}`
      : 'load_more_search_results';
    
    try {
      this.pushEventTo(this.el, eventName, {})
        .catch(error => {
          console.error('Error loading more items:', error);
          this.pending = false;
        });
    } catch (error) {
      console.error('Error pushing event:', error);
      this.pending = false;
    }
  },

  updated() {
    if (this.el.dataset.loading !== "true") {
      this.pending = false;

      // Re-append sentinel for filter lists if needed
      if (this.containerType === "filter") {
        const targetContainer = this.el.querySelector('ul.menu');
        if (targetContainer && !targetContainer.querySelector('.loading-sentinel')) {
          targetContainer.appendChild(this.sentinel);
        }
      }
    }
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  }
};

export default InfiniteScroll;