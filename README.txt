WEB BROWSER (browser-in-a-browser) - SETUP
==========================================

1. Unzip, then in a terminal:
       cd web-browser-setup
       chmod +x setup.sh
       ./setup.sh

2. Open http://localhost:1267 in Chrome, Firefox or Edge on the same computer.

The script installs git/curl, Node.js 24 (if you don't already have
Node 20+), downloads the Ultraviolet proxy, adds the tabbed UI, and runs it
as a service called "web-browser" that starts automatically on boot.

Options
  ./setup.sh --foreground   run in the terminal instead of as a service
  ./setup.sh --uninstall    remove everything
  PORT=8080 ./setup.sh      use a different port

Using it from OTHER devices (phones, other PCs)
  The proxy relies on a browser "service worker". Browsers only allow those
  on https:// pages or on localhost, so http://<your-ip>:1267 will show
  "Failed to register service worker" from another device.
  Fixes:
   - Put it behind HTTPS with a domain, e.g. Caddy:
       your.domain.com {
           reverse_proxy localhost:1267
       }
   - Or a quick tunnel, no domain needed:
       cloudflared tunnel --url http://localhost:1267
   - For testing only, in Chrome on the other device go to
     chrome://flags/#unsafely-treat-insecure-origin-as-secure
     and add http://<your-ip>:1267

Troubleshooting
  sudo systemctl status web-browser
  sudo journalctl -u web-browser -n 50
