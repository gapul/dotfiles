<template>
  <div class="w-full">
    <!-- Label -->
    <label
      v-if="label"
      :for="inputId"
      class="block text-sm font-medium text-gray-700 mb-1"
    >
      {{ label }}
      <span
        v-if="required"
        class="text-red-500 ml-1"
      >*</span>
    </label>

    <!-- Input container -->
    <div class="relative">
      <!-- Left icon -->
      <div
        v-if="leftIcon"
        class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none"
      >
        <component
          :is="leftIcon"
          :class="[
            'h-5 w-5',
            error ? 'text-red-400' : 'text-gray-400'
          ]"
        />
      </div>

      <!-- Input field -->
      <input
        :id="inputId"
        :type="type"
        :value="modelValue"
        :placeholder="placeholder"
        :disabled="disabled"
        :readonly="readonly"
        :required="required"
        :class="inputClasses"
        @input="handleInput"
        @blur="handleBlur"
        @focus="handleFocus"
      />

      <!-- Right icon -->
      <div
        v-if="rightIcon"
        class="absolute inset-y-0 right-0 pr-3 flex items-center"
        :class="{ 'pointer-events-none': !rightIconClickable }"
        @click="handleRightIconClick"
      >
        <component
          :is="rightIcon"
          :class="[
            'h-5 w-5',
            rightIconClickable ? 'cursor-pointer hover:text-gray-600' : '',
            error ? 'text-red-400' : 'text-gray-400'
          ]"
        />
      </div>
    </div>

    <!-- Hint text -->
    <p
      v-if="hint && !error"
      class="mt-1 text-sm text-gray-500"
    >
      {{ hint }}
    </p>

    <!-- Error message -->
    <p
      v-if="error"
      class="mt-1 text-sm text-red-600"
    >
      {{ error }}
    </p>
  </div>
</template>

<script setup lang="ts">
  import { computed, ref } from 'vue'
  import type { BaseInputProps } from '@/types'

  interface Props extends BaseInputProps {
    leftIcon?: any
    rightIcon?: any
    rightIconClickable?: boolean
  }

  interface Emits {
    'update:modelValue': [value: string | number]
    blur: [event: FocusEvent]
    focus: [event: FocusEvent]
    'right-icon-click': []
  }

  const props = withDefaults(defineProps<Props>(), {
    type: 'text',
    size: 'md',
    disabled: false,
    readonly: false,
    required: false,
    rightIconClickable: false,
  })

  const emit = defineEmits<Emits>()

  // Generate unique ID for input
  const inputId = ref(`input-${Math.random().toString(36).substr(2, 9)}`)

  // Base input classes
  const baseClasses = 'block w-full border-gray-300 rounded-md shadow-sm focus:ring-primary-500 focus:border-primary-500 disabled:bg-gray-50 disabled:text-gray-500 disabled:cursor-not-allowed transition-colors duration-200'

  // Size classes
  const sizeClasses = computed(() => {
    const sizes = {
      sm: 'px-3 py-2 text-sm',
      md: 'px-3 py-2 text-sm',
      lg: 'px-4 py-3 text-base',
    }
    return sizes[props.size]
  })

  // Padding adjustments for icons
  const paddingClasses = computed(() => {
    const leftPadding = props.leftIcon ? 'pl-10' : ''
    const rightPadding = props.rightIcon ? 'pr-10' : ''
    return `${leftPadding} ${rightPadding}`.trim()
  })

  // Error state classes
  const errorClasses = computed(() => {
    return props.error
      ? 'border-red-300 text-red-900 placeholder-red-300 focus:ring-red-500 focus:border-red-500'
      : ''
  })

  // Combined input classes
  const inputClasses = computed(() => [
    baseClasses,
    sizeClasses.value,
    paddingClasses.value,
    errorClasses.value,
  ])

  function handleInput(event: Event): void {
    const target = event.target as HTMLInputElement
    const value = props.type === 'number' ? Number(target.value) : target.value
    emit('update:modelValue', value)
  }

  function handleBlur(event: FocusEvent): void {
    emit('blur', event)
  }

  function handleFocus(event: FocusEvent): void {
    emit('focus', event)
  }

  function handleRightIconClick(): void {
    if (props.rightIconClickable) {
      emit('right-icon-click')
    }
  }
</script>