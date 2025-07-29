# Vue.js + TypeScript Template Configuration
{
  name = "vue-typescript";
  displayName = "Vue.js + TypeScript";
  description = "Modern Vue.js 3 application with TypeScript, Vite, and comprehensive tooling";
  
  type = "frontend";
  framework = "vue";
  language = "typescript";
  
  features = [
    "vue3"           # Vue.js 3 Composition API
    "typescript"     # Full TypeScript support
    "vite"           # Fast build tool
    "vue-router"     # Client-side routing
    "pinia"          # State management
    "tailwindcss"    # Utility-first CSS
    "headlessui"     # Accessible UI components
    "vueuse"         # Vue composition utilities
    "testing"        # Vitest + Vue Test Utils
    "eslint"         # Code linting
    "prettier"       # Code formatting
    "husky"          # Git hooks
  ];
  
  dependencies = [
    "vue"
    "vue-router"
    "pinia"
    "@vueuse/core"
    "@headlessui/vue"
    "@heroicons/vue"
    "axios"
    "zod"
    "date-fns"
  ];
  
  devDependencies = [
    "typescript"
    "vue-tsc"
    "@vitejs/plugin-vue"
    "vite"
    "@vue/test-utils"
    "vitest"
    "jsdom"
    "@types/node"
    "tailwindcss"
    "@tailwindcss/forms"
    "@tailwindcss/typography"
    "autoprefixer"
    "postcss"
    "eslint"
    "@vue/eslint-config-typescript"
    "@vue/eslint-config-prettier"
    "eslint-plugin-vue"
    "prettier"
    "husky"
    "lint-staged"
  ];
  
  scripts = {
    dev = "vite";
    build = "vue-tsc && vite build";
    preview = "vite preview";
    test = "vitest";
    "test:ui" = "vitest --ui";
    "test:coverage" = "vitest --coverage";
    lint = "eslint . --ext .vue,.js,.jsx,.cjs,.mjs,.ts,.tsx,.cts,.mts --fix";
    format = "prettier --write src/";
    "type-check" = "vue-tsc --noEmit";
    prepare = "husky install";
  };
  
  files = [
    "package.json"
    "tsconfig.json"
    "tsconfig.app.json"
    "tsconfig.vitest.json"
    "vite.config.ts"
    "tailwind.config.js"
    "postcss.config.js"
    ".eslintrc.cjs"
    ".prettierrc"
    "vitest.config.ts"
    "index.html"
    "src/main.ts"
    "src/App.vue"
    "src/router/index.ts"
    "src/stores/index.ts"
    "src/stores/auth.ts"
    "src/stores/user.ts"
    "src/views/HomeView.vue"
    "src/views/LoginView.vue"
    "src/views/DashboardView.vue"
    "src/components/AppHeader.vue"
    "src/components/AppFooter.vue"
    "src/components/ui/BaseButton.vue"
    "src/components/ui/BaseInput.vue"
    "src/components/ui/BaseModal.vue"
    "src/composables/useApi.ts"
    "src/composables/useAuth.ts"
    "src/composables/useNotification.ts"
    "src/types/index.ts"
    "src/utils/api.ts"
    "src/utils/validation.ts"
    "src/assets/css/main.css"
    "public/favicon.ico"
    ".env.example"
    "README.md"
  ];
  
  nixPackages = [
    "nodejs_20"
    "typescript"
  ];
}