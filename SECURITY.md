# Security

Mettle is an experimental parser, compiler, and GPU renderer. It has input-size and geometry/allocation limits, but it is **not a sandbox** and has not had an independent security audit. Open only trusted exported scenes.

The Figma development plugin requests no network access. The runtime renders local scene data. No font files, credentials, or private service tokens are required to use the library.

For a suspected vulnerability, use GitHub's private vulnerability reporting for this repository when available. Do not post exploit payloads containing sensitive data, credentials, or private designs in public issues. There is no guaranteed response time or production support commitment.
