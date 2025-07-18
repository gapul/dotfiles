<template>
  <button
    :type="type"
    :disabled="disabled || loading"
    :class="buttonClasses"
    @click="handleClick"
  >
    <!-- Loading spinner -->
    <svg
      v-if="loading"
      class="animate-spin h-4 w-4 mr-2"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
    >
      <circle
        class="opacity-25"
        cx="12"
        cy="12"
        r="10"
        stroke="currentColor"
        stroke-width="4"
      />
      <path
        class="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>

    <!-- Icon (left) -->
    <component
      v-if="leftIcon && !loading"
      :is="leftIcon"
      :class="iconClasses"
    />

    <!-- Button text -->
    <span v-if="$slots.default || label">
      <slot>{{ label }}</slot>
    </span>

    <!-- Icon (right) -->
    <component
      v-if="rightIcon && !loading"
      :is="rightIcon"
      :class="[iconClasses, $slots.default || label ? 'ml-2' : '']"
    />
  </button>
</template>

<script setup lang="ts">
  import { computed } from 'vue'
  import type { BaseButtonProps } from '@/types'

  interface Props extends BaseButtonProps {
    label?: string
    leftIcon?: any
    rightIcon?: any
  }

  interface Emits {
    click: [event: MouseEvent]
  }

  const props = withDefaults(defineProps<Props>(), {
    variant: 'primary',
    size: 'md',
    type: 'button',
    loading: false,
    disabled: false,
    block: false,
  })

  const emit = defineEmits<Emits>()

  // Base classes
  const baseClasses = 'inline-flex items-center justify-center font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 transition-colors duration-200 disabled:opacity-50 disabled:cursor-not-allowed'

  // Variant classes
  const variantClasses = computed(() => {
    const variants = {
      primary: 'bg-primary-600 hover:bg-primary-700 text-white focus:ring-primary-500',
      secondary: 'bg-gray-600 hover:bg-gray-700 text-white focus:ring-gray-500',
      success: 'bg-green-600 hover:bg-green-700 text-white focus:ring-green-500',
      danger: 'bg-red-600 hover:bg-red-700 text-white focus:ring-red-500',
      warning: 'bg-yellow-600 hover:bg-yellow-700 text-white focus:ring-yellow-500',
      info: 'bg-blue-600 hover:bg-blue-700 text-white focus:ring-blue-500',
      light: 'bg-gray-100 hover:bg-gray-200 text-gray-900 focus:ring-gray-500',
      dark: 'bg-gray-900 hover:bg-gray-800 text-white focus:ring-gray-500',
    }
    return variants[props.variant]
  })

  // Size classes
  const sizeClasses = computed(() => {
    const sizes = {
      xs: 'px-2.5 py-1.5 text-xs',
      sm: 'px-3 py-2 text-sm',
      md: 'px-4 py-2 text-sm',
      lg: 'px-4 py-2 text-base',
      xl: 'px-6 py-3 text-base',
    }
    return sizes[props.size]
  })

  // Icon classes
  const iconClasses = computed(() => {
    const sizes = {
      xs: 'h-3 w-3',
      sm: 'h-4 w-4',
      md: 'h-4 w-4',
      lg: 'h-5 w-5',
      xl: 'h-5 w-5',
    }
    return sizes[props.size]
  })

  // Combined classes
  const buttonClasses = computed(() => [
    baseClasses,
    variantClasses.value,
    sizeClasses.value,
    {
      'w-full': props.block,
      'cursor-not-allowed': props.disabled || props.loading,
    },
  ])

  function handleClick(event: MouseEvent): void {
    if (!props.disabled && !props.loading) {
      emit('click', event)
    }
  }
</script>