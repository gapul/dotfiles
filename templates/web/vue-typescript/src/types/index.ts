// User types
export interface User {
  id: string
  name: string
  email: string
  role: 'admin' | 'user'
  isActive: boolean
  avatar?: string
  createdAt: string
  updatedAt: string
  lastLoginAt?: string
}

export interface LoginCredentials {
  email: string
  password: string
}

export interface RegisterData {
  name: string
  email: string
  password: string
  confirmPassword: string
}

// API Response types
export interface ApiResponse<T = any> {
  success: boolean
  message: string
  data: T
}

export interface PaginatedResponse<T = any> {
  success: boolean
  data: T[]
  meta: {
    page: number
    limit: number
    total: number
    totalPages: number
  }
}

export interface ErrorResponse {
  success: false
  error: string
  message: string
  statusCode: number
  timestamp: string
  path: string
  details?: any
}

// Form types
export interface FormField {
  label: string
  type: 'text' | 'email' | 'password' | 'select' | 'textarea' | 'checkbox' | 'radio'
  name: string
  placeholder?: string
  required?: boolean
  options?: { value: string; label: string }[]
  validation?: {
    min?: number
    max?: number
    pattern?: RegExp
    message?: string
  }
}

export interface FormData {
  [key: string]: any
}

export interface FormErrors {
  [key: string]: string | undefined
}

// Component props types
export interface BaseButtonProps {
  variant?: 'primary' | 'secondary' | 'success' | 'danger' | 'warning' | 'info' | 'light' | 'dark'
  size?: 'xs' | 'sm' | 'md' | 'lg' | 'xl'
  loading?: boolean
  disabled?: boolean
  type?: 'button' | 'submit' | 'reset'
  block?: boolean
}

export interface BaseInputProps {
  modelValue?: string | number
  type?: 'text' | 'email' | 'password' | 'number' | 'tel' | 'url' | 'search'
  placeholder?: string
  disabled?: boolean
  readonly?: boolean
  required?: boolean
  error?: string
  label?: string
  hint?: string
  size?: 'sm' | 'md' | 'lg'
}

export interface BaseModalProps {
  modelValue: boolean
  title?: string
  size?: 'sm' | 'md' | 'lg' | 'xl' | 'full'
  persistent?: boolean
  showClose?: boolean
  closeOnEscape?: boolean
  closeOnBackdrop?: boolean
}

// Navigation types
export interface NavigationItem {
  name: string
  href?: string
  to?: string
  icon?: any
  current?: boolean
  children?: NavigationItem[]
  requiresAuth?: boolean
  roles?: string[]
}

// Theme types
export interface ThemeConfig {
  primary: string
  secondary: string
  accent: string
  neutral: string
  success: string
  warning: string
  error: string
  info: string
}

// Filter and search types
export interface FilterOptions {
  search?: string
  role?: string
  status?: string
  sortBy?: string
  sortOrder?: 'asc' | 'desc'
  page?: number
  limit?: number
}

export interface SortOption {
  key: string
  label: string
  defaultOrder?: 'asc' | 'desc'
}

// File upload types
export interface FileUpload {
  file: File
  progress: number
  status: 'pending' | 'uploading' | 'success' | 'error'
  error?: string
  url?: string
}

// Settings types
export interface UserSettings {
  theme: 'light' | 'dark' | 'auto'
  language: string
  timezone: string
  notifications: {
    email: boolean
    push: boolean
    desktop: boolean
  }
  privacy: {
    profileVisible: boolean
    activityVisible: boolean
  }
}

// Chart/Analytics types
export interface ChartDataPoint {
  label: string
  value: number
  color?: string
}

export interface TimeSeriesData {
  date: string
  value: number
}

export interface AnalyticsData {
  users: {
    total: number
    active: number
    new: number
    growth: number
  }
  activity: {
    daily: TimeSeriesData[]
    weekly: TimeSeriesData[]
    monthly: TimeSeriesData[]
  }
  demographics: ChartDataPoint[]
}

// Utility types
export type Optional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>
export type RequiredFields<T, K extends keyof T> = T & Required<Pick<T, K>>

// Event types
export interface CustomEvent<T = any> {
  type: string
  payload: T
  timestamp: number
}

// Route meta types
declare module 'vue-router' {
  interface RouteMeta {
    title?: string
    requiresAuth?: boolean
    hideForAuth?: boolean
    roles?: string[]
    layout?: string
  }
}