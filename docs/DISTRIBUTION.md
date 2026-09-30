# Distribution: local now, Community later

## Recommendation

Keep the **public GitHub repository + local development-plugin install** as the primary route for the experimental build. This is not a choice between “a plugin” and “local code”: the exporter is already a Figma plugin. The choice is **local installation versus a discoverable Community listing**.

The desktop utility is optional. The main workflow is Figma plugin → exported scene → native Swift library. Publishing the exporter does not make Metal run inside Figma and does not remove the native integration step.

## What to ship now

Provide the [local setup guide](LOCAL_SETUP.md), prebuilt plugin JS, optional plugin-only ZIP packaging, compatibility matrix, bug-report template, and independent validation fixtures. Keep “Experimental” visible. The README should lead with the workflow, not primitive test artwork.

## Gate before Community submission

These are our proposed engineering gates, not Figma approval criteria:

- Three independent people can install from scratch, export a supported file, and preview it without help.
- Five deliberately scoped, visually useful Figma examples have been exported and compared frame by frame; describe any fidelity differences.
- Actual Figma Desktop import/panel/download/cleanup has been exercised, not just the shared capture logic through the connector.
- Unsupported features produce clear errors, and the file schema/version behavior is documented.
- The listing’s images show actual Mettle output. External reference work is never presented as a native compatibility claim.

## Public publishing requirements

Figma’s current classic-plugin guide requires the desktop app, a development plugin, and two-factor authentication. Community submissions go through review. The guide asks for a name, tagline, description/category, icon, thumbnail, support contact, and network-access review; a playground and more screenshots are optional. The manifest documentation explains how to obtain a Figma-assigned plugin ID.

Once ready, submit **Mettle — Experimental Metal Export** as a free Community plugin, while keeping local installation available for contributors. A playground with one small verified animation should accompany the listing. Publication is a separate explicit step; none of the setup/package scripts submit anything.

## Sources, checked 2026-09-30

- [Publish classic plugins](https://help.figma.com/hc/en-us/articles/360042293394-Publish-classic-plugins-to-the-Figma-Community)
- [Development plugin import](https://help.figma.com/hc/en-us/articles/360042786733-Create-a-plugin-for-development)
- [Plugin manifest](https://developers.figma.com/docs/plugins/manifest/)
- [Playground files](https://help.figma.com/hc/en-us/articles/10550242467991-Playground-files-for-widgets-and-plugins)
