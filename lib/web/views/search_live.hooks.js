let InfiniteScroll = {
  mounted() {
    console.log("InfiniteScroll hook mounted", this.el.id);
    
    this.pending = false;
    this.initialLoad = true;
    
    // Create a sentinel element for intersection detection
    this.sentinel = document.createElement(this.el.tagName === 'UL' ? 'li' : 'div');
    this.sentinel.classList.add('loading-sentinel');
    this.sentinel.setAttribute('phx-update', 'ignore');
    
    this.sentinel.style.cssText = `
      height: auto;
      width: 100%;
      list-style: none;
      padding: 0;
      margin: 0;
      order: 9999;
    `;

    // Determine if we're using a menu container or the main scrollbar
    const isSearchResults = this.el.id === 'search_results';
    const targetContainer = isSearchResults ? this.el : this.el.querySelector('ul.menu');
    
    if (targetContainer) {
      targetContainer.appendChild(this.sentinel);
      
      this.observer = new IntersectionObserver(
        (entries) => this.onIntersect(entries),
        {
          root: null,
          threshold: 0,
          rootMargin: "100px 0px 0px 0px"
        }
      );
      
      this.observer.observe(this.sentinel);
    }
  },

  onIntersect(entries) {
    const entry = entries[0];
    const loading = this.el.dataset.loading === "true";
    
    if (entry.isIntersecting && !this.pending && !loading) {
      this.pending = true;
      
      const eventName = this.el.id === 'search_results' 
        ? 'load_more_search_results'
        : `load_more_${this.el.id.replace('-container', '')}`;
      
      this.pushEventTo(this.el, eventName, {});
    }
  },

  updated() {
    this.pending = false;
    const loading = this.el.dataset.loading === "true";
    
    if (!loading && this.sentinel) {
      // Re-append sentinel if needed
      const targetContainer = this.el.id === 'search_results' ? this.el : this.el.querySelector('ul.menu');
      if (targetContainer && !targetContainer.querySelector('.loading-sentinel')) {
        targetContainer.appendChild(this.sentinel);
      }
    }
  }
};

export default InfiniteScroll;