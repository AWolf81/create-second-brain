1. Push this repository to a GitLab project named `__APP_NAME__`.
2. **Turn on Pages access control** — Settings → General → *Visibility, project features,
   permissions* → Pages → enable access control. Until you do this **the site is public**.
   Only project members (Guest and above) can view it once enabled.
3. Set `baseUrl` in `site/quartz.config.yaml` to your real Pages host
   (`<namespace>.gitlab.io/__APP_NAME__`). Self-hosted fonts use absolute URLs and 404
   silently if it is wrong.
4. Push to your default branch — the pipeline builds and publishes.

GitLab Free includes 400 CI minutes a month; a build costs roughly 2–4.
