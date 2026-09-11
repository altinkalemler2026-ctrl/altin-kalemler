import path from "node:path"
import { fileURLToPath } from "node:url"

import react from "@vitejs/plugin-react"
import { defineConfig } from "vitest/config"

const rootDir = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(rootDir, "src"),
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.test.{ts,tsx}"],
    // Yerelde integration testleri E2E_DB_CONTAINER ortami ile calistirilir;
    // env yoksa vitest bunlari otomatik olarak atlar.
    exclude: process.env.E2E_DB_CONTAINER
      ? []
      : ["src/**/integration.local.test.ts"],
    testTimeout: 30_000,
    // Entegrasyon hook'lari admin kullanici olusturma + fixture
    // yukleme + auth girisi yapar; CI runner'inda 30 sn asilabilir.
    // CI'daki Supabase DB hazirlik penceresiyle ayni sinir: 120 sn.
    hookTimeout: 120_000,
  },
})
