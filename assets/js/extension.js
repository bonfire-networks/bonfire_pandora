/**
 * JS hooks exported for the PanDoRa / bonfire_pandora extension.
 * Imported by the umbrella `config/deps.hooks.js` (and flavour overrides).
 * Add new LiveView hooks here so a fresh Bonfire + federated_archives install gets them.
 */
import PlyrInit from "../../lib/web/hooks/plyr_init.hooks.js";

export const PandoraHooks = {
  PlyrInit,
};

export default PandoraHooks;
