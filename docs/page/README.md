# LiteDeploy Docs

Documentation site for [LiteDeploy-Core](https://github.com/cmartinezone/LiteDeploy-Core), built with [Astro](https://astro.build) and [Starlight](https://starlight.astro.build) — the same stack as [WinUtil](https://winutil.christitus.com/).

Long-form design notes stay in [`docs/architecture/`](../architecture/). This folder is the curated site.

## Commands

From `docs/page`:

```powershell
npm install
npm run dev      # http://localhost:4321
npm run build    # ./dist
npm run preview
```

## Layout

```text
docs/page/
  src/content/docs/          Markdown / MDX pages
    index.mdx                Landing
    guides/                  User guide
    code-reference/          Architecture + components
    manager/
    help/
  astro.config.mjs           Sidebar and theme
```

File path becomes the URL: `code-reference/bootinitializer.mdx` → `/code-reference/bootinitializer/`.

Keep sidebar slugs in `astro.config.mjs` in sync when you add a page.
