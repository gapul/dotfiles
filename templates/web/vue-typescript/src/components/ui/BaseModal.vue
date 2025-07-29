<template>
  <TransitionRoot
    :show="modelValue"
    as="template"
  >
    <Dialog
      as="div"
      class="relative z-50"
      @close="handleClose"
    >
      <!-- Backdrop -->
      <TransitionChild
        as="template"
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0"
      >
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" />
      </TransitionChild>

      <!-- Modal container -->
      <div class="fixed inset-0 z-10 overflow-y-auto">
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <TransitionChild
            as="template"
            enter="ease-out duration-300"
            enter-from="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
            enter-to="opacity-100 translate-y-0 sm:scale-100"
            leave="ease-in duration-200"
            leave-from="opacity-100 translate-y-0 sm:scale-100"
            leave-to="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
          >
            <DialogPanel :class="modalClasses">
              <!-- Header -->
              <div
                v-if="title || showClose"
                class="flex items-center justify-between p-4 border-b border-gray-200"
              >
                <DialogTitle
                  v-if="title"
                  as="h3"
                  class="text-lg font-medium leading-6 text-gray-900"
                >
                  {{ title }}
                </DialogTitle>
                <div v-else />

                <button
                  v-if="showClose"
                  type="button"
                  class="rounded-md text-gray-400 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-primary-500"
                  @click="handleClose"
                >
                  <span class="sr-only">Close</span>
                  <XMarkIcon class="h-6 w-6" />
                </button>
              </div>

              <!-- Content -->
              <div class="p-4">
                <slot />
              </div>

              <!-- Footer -->
              <div
                v-if="$slots.footer"
                class="flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2 p-4 border-t border-gray-200 space-y-2 space-y-reverse sm:space-y-0"
              >
                <slot name="footer" />
              </div>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>

<script setup lang="ts">
  import { computed, onMounted, onUnmounted } from 'vue'
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue'
  import { XMarkIcon } from '@heroicons/vue/24/outline'
  import type { BaseModalProps } from '@/types'

  interface Emits {
    'update:modelValue': [value: boolean]
    close: []
  }

  const props = withDefaults(defineProps<BaseModalProps>(), {
    size: 'md',
    persistent: false,
    showClose: true,
    closeOnEscape: true,
    closeOnBackdrop: true,
  })

  const emit = defineEmits<Emits>()

  // Modal size classes
  const sizeClasses = computed(() => {
    const sizes = {
      sm: 'max-w-md',
      md: 'max-w-lg',
      lg: 'max-w-2xl',
      xl: 'max-w-4xl',
      full: 'max-w-7xl',
    }
    return sizes[props.size]
  })

  // Combined modal classes
  const modalClasses = computed(() => [
    'relative transform overflow-hidden rounded-lg bg-white text-left shadow-xl transition-all',
    sizeClasses.value,
    'w-full',
  ])

  function handleClose(): void {
    if (!props.persistent) {
      emit('update:modelValue', false)
      emit('close')
    }
  }

  // Handle escape key
  function handleEscape(event: KeyboardEvent): void {
    if (event.key === 'Escape' && props.closeOnEscape && props.modelValue) {
      handleClose()
    }
  }

  // Handle backdrop click
  function handleBackdropClick(event: MouseEvent): void {
    if (
      props.closeOnBackdrop &&
      props.modelValue &&
      event.target === event.currentTarget
    ) {
      handleClose()
    }
  }

  onMounted(() => {
    if (props.closeOnEscape) {
      document.addEventListener('keydown', handleEscape)
    }
  })

  onUnmounted(() => {
    if (props.closeOnEscape) {
      document.removeEventListener('keydown', handleEscape)
    }
  })
</script>