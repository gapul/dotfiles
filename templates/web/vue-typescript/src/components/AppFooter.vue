<template>
  <footer class="bg-gray-50 border-t border-gray-200">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <div class="grid grid-cols-1 md:grid-cols-4 gap-8">
        <!-- Brand -->
        <div class="col-span-1 md:col-span-2">
          <div class="flex items-center space-x-3 mb-4">
            <div class="h-8 w-8 bg-primary-600 rounded-lg flex items-center justify-center">
              <span class="text-white font-bold text-sm">{{PROJECT_NAME.charAt(0).toUpperCase()}}</span>
            </div>
            <span class="text-xl font-semibold text-gray-900">{{PROJECT_NAME}}</span>
          </div>
          <p class="text-gray-600 text-sm mb-4 max-w-md">
            Modern Vue.js application built with TypeScript, Vite, and Tailwind CSS.
            Designed for scalability and developer experience.
          </p>
          <div class="flex space-x-4">
            <a
              href="#"
              class="text-gray-400 hover:text-gray-600 transition-colors duration-200"
              aria-label="GitHub"
            >
              <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M10 0C4.477 0 0 4.484 0 10.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0110 4.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.203 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.942.359.31.678.921.678 1.856 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0020 10.017C20 4.484 15.522 0 10 0z"
                  clip-rule="evenodd"
                />
              </svg>
            </a>
            <a
              href="#"
              class="text-gray-400 hover:text-gray-600 transition-colors duration-200"
              aria-label="Twitter"
            >
              <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                <path d="M6.29 18.251c7.547 0 11.675-6.253 11.675-11.675 0-.178 0-.355-.012-.53A8.348 8.348 0 0020 3.92a8.19 8.19 0 01-2.357.646 4.118 4.118 0 001.804-2.27 8.224 8.224 0 01-2.605.996 4.107 4.107 0 00-6.993 3.743 11.65 11.65 0 01-8.457-4.287 4.106 4.106 0 001.27 5.477A4.073 4.073 0 01.8 7.713v.052a4.105 4.105 0 003.292 4.022 4.095 4.095 0 01-1.853.07 4.108 4.108 0 003.834 2.85A8.233 8.233 0 010 16.407a11.616 11.616 0 006.29 1.84" />
              </svg>
            </a>
          </div>
        </div>

        <!-- Quick Links -->
        <div>
          <h3 class="text-sm font-semibold text-gray-900 tracking-wider uppercase mb-4">
            Quick Links
          </h3>
          <ul class="space-y-3">
            <li>
              <router-link
                to="/"
                class="text-gray-600 hover:text-gray-900 text-sm transition-colors duration-200"
              >
                Home
              </router-link>
            </li>
            <li>
              <router-link
                to="/about"
                class="text-gray-600 hover:text-gray-900 text-sm transition-colors duration-200"
              >
                About
              </router-link>
            </li>
            <li v-if="isAuthenticated">
              <router-link
                to="/dashboard"
                class="text-gray-600 hover:text-gray-900 text-sm transition-colors duration-200"
              >
                Dashboard
              </router-link>
            </li>
            <li v-if="!isAuthenticated">
              <router-link
                to="/login"
                class="text-gray-600 hover:text-gray-900 text-sm transition-colors duration-200"
              >
                Sign In
              </router-link>
            </li>
          </ul>
        </div>

        <!-- Support -->
        <div>
          <h3 class="text-sm font-semibold text-gray-900 tracking-wider uppercase mb-4">
            Support
          </h3>
          <ul class="space-y-3">
            <li>
              <a
                href="#"
                class="text-gray-600 hover:text-gray-900 text-sm transition-colors duration-200"
              >
                Documentation
              </a>
            </li>
            <li>
              <a
                href="#"
                class="text-gray-600 hover:text-gray-900 text-sm transition-colors duration-200"
              >
                Help Center
              </a>
            </li>
            <li>
              <a
                href="#"
                class="text-gray-600 hover:text-gray-900 text-sm transition-colors duration-200"
              >
                Contact Us
              </a>
            </li>
            <li>
              <a
                href="#"
                class="text-gray-600 hover:text-gray-900 text-sm transition-colors duration-200"
              >
                Status
              </a>
            </li>
          </ul>
        </div>
      </div>

      <!-- Bottom section -->
      <div class="mt-8 pt-8 border-t border-gray-200 flex flex-col md:flex-row justify-between items-center">
        <div class="flex flex-col md:flex-row items-center space-y-2 md:space-y-0 md:space-x-6">
          <p class="text-gray-500 text-sm">
            © {{ currentYear }} {{PROJECT_NAME}}. All rights reserved.
          </p>
          <div class="flex items-center space-x-6">
            <a
              href="#"
              class="text-gray-500 hover:text-gray-700 text-sm transition-colors duration-200"
            >
              Privacy Policy
            </a>
            <a
              href="#"
              class="text-gray-500 hover:text-gray-700 text-sm transition-colors duration-200"
            >
              Terms of Service
            </a>
            <a
              href="#"
              class="text-gray-500 hover:text-gray-700 text-sm transition-colors duration-200"
            >
              Cookie Policy
            </a>
          </div>
        </div>
        
        <div class="mt-4 md:mt-0 flex items-center space-x-2 text-sm text-gray-500">
          <span>Built with</span>
          <span class="text-green-600">Vue 3</span>
          <span>&</span>
          <span class="text-blue-600">TypeScript</span>
        </div>
      </div>
    </div>
  </footer>
</template>

<script setup lang="ts">
  import { computed } from 'vue'
  import { useAuth } from '@/composables/useAuth'
  
  const { isAuthenticated } = useAuth()
  
  const currentYear = computed(() => new Date().getFullYear())
</script>