let InfiniteScroll = {
  mounted() {
    console.log("InfiniteScroll hook mounted", this.el.id);
    
    this.pending = false;
    this.initialLoad = true;
    
    // Create a sentinel element for intersection detection
    this.sentinel = document.createElement(this.el.tagName === 'UL' ? 'li' : 'div');
    this.sentinel.classList.add('loading-sentinel');
    this.sentinel.setAttribute('phx-update', 'ignore');
    
    // Create spinner element
    const spinner = document.createElement('div');
    spinner.classList.add('loader', 'hidden');
    spinner.innerHTML = `
      <div class="p-3 flex items-center justify-center z-10">
        <div class="loading loading-spinner loading-lg text-primary" />
      </div>
    `;
    
    this.sentinel.appendChild(spinner);
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
    const menuList = this.el.querySelector('ul.menu');
    const targetContainer = isSearchResults ? this.el : menuList;
    
    if (targetContainer) {
      console.log("Found target container:", targetContainer.id || 'main content');
      
      if (targetContainer === this.el) {
        // For search results, append to the element itself
        targetContainer.appendChild(this.sentinel);
        
        // Use viewport as root for main scrollbar
        this.observer = new IntersectionObserver(
          (entries) => this.onIntersect(entries),
          {
            root: null, // Use viewport
            threshold: 0,
            rootMargin: "100px 0px 0px 0px" // Increased margin for earlier trigger
          }
        );
      } else {
        // For menu containers, ensure proper styling
        targetContainer.style.position = 'relative';
        targetContainer.style.display = 'flex';
        targetContainer.style.flexDirection = 'column';
        targetContainer.appendChild(this.sentinel);
        
        // Use menu container as root
        this.observer = new IntersectionObserver(
          (entries) => this.onIntersect(entries),
          {
            root: targetContainer,
            threshold: 0,
            rootMargin: "10px 0px 0px 0px"
          }
        );
      }

      this.observer.observe(this.sentinel);
      console.log("Sentinel appended and observing");
    } else {
      console.warn("Target container not found in", this.el.id);
    }
  },

  onIntersect(entries) {
    const entry = entries[0];
    console.log("Intersection detected", {
      isIntersecting: entry.isIntersecting,
      pending: this.pending,
      elementId: this.el.id,
      initialLoad: this.initialLoad
    });

    if (this.initialLoad) {
      this.initialLoad = false;
      return;
    }

    if (entry.isIntersecting && !this.pending) {
      this.pending = true;
      
      const spinner = this.sentinel.querySelector('.loader');
      if (spinner) spinner.classList.remove('hidden');
      
      // Handle both search results and filter cases
      const eventName = this.el.id === 'search_results' 
        ? 'Bonfire.PanDoRa.Web.SearchLive:load_more_search_results'  // Use module prefix for stream
        : `load_more_${this.el.id.replace('-container', '')}`;  // Keep simple format for append
      
      try {
        console.log("Pushing event", eventName);
        this.pushEventTo(this.el, eventName, {});
      } catch (error) {
        console.error("Error pushing event:", error);
      }
    }
  },

  updated() {
    console.log("Hook updated", this.el.id);
    
    // Reset pending state after update
    this.pending = false;
    
    if (this.sentinel) {
      const spinner = this.sentinel.querySelector('.loader');
      if (spinner) spinner.classList.add('hidden');
    }
    
    // Re-append sentinel if needed
    const isSearchResults = this.el.id === 'search_results';
    const targetContainer = isSearchResults ? this.el : this.el.querySelector('ul.menu');
    
    if (targetContainer && !targetContainer.querySelector('.loading-sentinel')) {
      console.log("Re-appending sentinel after update");
      targetContainer.appendChild(this.sentinel);
    }
  },

  destroyed() {
    console.log("Hook destroyed", this.el.id);
    if (this.observer) {
      this.observer.disconnect();
    }
    if (this.sentinel && this.sentinel.parentNode) {
      this.sentinel.parentNode.removeChild(this.sentinel);
    }
  }
};

export default InfiniteScroll;