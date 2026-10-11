import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

export default defineConfig({
  // Relative URLs: the site works under GitHub Pages' /colophon/ as on a domain of its own.
  base: "./",
  plugins: [tailwindcss()],
  // The page takes its screenshot and icons from the repository, outside the site's folder.
  server: { fs: { allow: [".."] } },
});
