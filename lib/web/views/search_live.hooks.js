let InfiniteScroll = {
  mounted() {
    this.initialize();
  },

  initialize() {
    this.pending = false;
    this.containerType = this.el.dataset.type;
    this.isStable = true;
    this.resizeTimeout = null;
    this.isScrolling = false;
    this.scrollTimeout = null;
    
    if (this.containerType === "filter") {
      this.setupFilterSentinel();
    } else {
      this.setupResultsSentinel();
    }

    this.setupResizeObserver();
    this.setupScrollListener();
  },

  getContainer() {
    return this.containerType === "filter" 
      ? this.el.querySelector('ul.menu')
      : this.el;
  },

  setupScrollListener() {
    const container = this.getContainer();
    if (!container) return;

    const handleScroll = () => {
      this.isScrolling = true;
      
      if (this.scrollTimeout) {
        clearTimeout(this.scrollTimeout);
      }
      
      this.scrollTimeout = setTimeout(() => {
        this.isScrolling = false;
      }, 100);
    };

    if (this.containerType === "filter") {
      // For filters, only watch container scroll
      container.addEventListener('scroll', handleScroll, { passive: true });
    } else {
      // For main results, only watch window scroll
      window.addEventListener('scroll', handleScroll, { passive: true });
    }
  },

  hasItems() {
    const container = this.getContainer();
    if (!container) return false;
    
    if (this.containerType === "filter") {
      return container.querySelectorAll('li').length > 0;
    }
    
    return container.children.length > 1;
  },

  setupResizeObserver() {
    const container = this.getContainer();
    if (!container) return;

    this.resizeObserver = new ResizeObserver(() => {
      this.isStable = false;
      if (this.resizeTimeout) {
        clearTimeout(this.resizeTimeout);
      }
      this.resizeTimeout = setTimeout(() => {
        this.isStable = true;
      }, 150);
    });

    this.resizeObserver.observe(container);
  },

  setupFilterSentinel() {
    // For filters, always setup sentinel
    this.sentinel = document.createElement('div');
    this.sentinel.classList.add('loading-sentinel');
    this.sentinel.setAttribute('phx-update', 'ignore');
    this.sentinel.style.cssText = 'height: 20px; width: 100%;';

    const container = this.getContainer();
    if (container) {
      container.appendChild(this.sentinel);
      this.setupObserver();
    }
  },

  setupResultsSentinel() {
    this.sentinel = document.getElementById('search-results-sentinel');
    if (this.sentinel && this.hasItems()) {
      this.setupObserver();
    }
  },

  setupObserver() {
    if (!this.sentinel) return;

    // For filters, observe relative to the container
    const options = {
      root: this.containerType === "filter" ? this.getContainer() : null,
      threshold: 0,
      rootMargin: "0px 0px 50px 0px" // Smaller margin for filters
    };

    this.observer = new IntersectionObserver(
      (entries) => this.handleIntersection(entries),
      options
    );
    
    this.observer.observe(this.sentinel);
  },

  handleIntersection(entries) {
    const entry = entries[0];
    
    // Different checks for filters vs search results
    if (this.containerType === "filter") {
      if (!entry.isIntersecting || 
          this.pending || 
          this.el.dataset.loading === "true" ||
          !this.isScrolling) {  // Only load if user has scrolled the container
        return;
      }
    } else {
      // Main search results need more strict checks
      if (!entry.isIntersecting || 
          this.pending || 
          this.el.dataset.loading === "true" ||
          !this.isStable ||
          !this.hasItems() ||
          !this.isScrolling) {
        return;
      }
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

      if (this.containerType === "filter") {
        const container = this.getContainer();
        if (container && !container.querySelector('.loading-sentinel')) {
          container.appendChild(this.sentinel);
        }
      }
    }
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
    if (this.resizeTimeout) {
      clearTimeout(this.resizeTimeout);
    }
    if (this.scrollTimeout) {
      clearTimeout(this.scrollTimeout);
    }
    
    const container = this.getContainer();
    if (container) {
      container.removeEventListener('scroll', this.handleScroll);
    }
    window.removeEventListener('scroll', this.handleScroll);
  }
}

export default InfiniteScroll;