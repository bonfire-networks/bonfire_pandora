/**
 * Keeps <details> open/closed state across LiveView patches.
 * Without this, re-rendering a sidebar widget resets native <details> and the
 * panel appears to toggle on every IN/OUT or form update.
 */
const PandoraPreserveDetailsOpen = {
  mounted() {
    this.open = this.el.open;
    this.onToggle = () => {
      this.open = this.el.open;
    };
    this.el.addEventListener("toggle", this.onToggle);
  },

  beforeUpdate() {
    this.open = this.el.open;
  },

  updated() {
    this.el.open = this.open;
  },

  destroyed() {
    this.el.removeEventListener("toggle", this.onToggle);
  },
};

export default PandoraPreserveDetailsOpen;
