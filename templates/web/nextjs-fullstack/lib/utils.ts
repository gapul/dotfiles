import { type ClassValue, clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

// Format utilities
export const formatters = {
  // Currency formatter
  currency: (amount: number, currency = 'USD') => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency,
    }).format(amount)
  },

  // Number formatter
  number: (num: number, options?: Intl.NumberFormatOptions) => {
    return new Intl.NumberFormat('en-US', options).format(num)
  },

  // Date formatter
  date: (date: Date | string, options?: Intl.DateTimeFormatOptions) => {
    const dateObj = typeof date === 'string' ? new Date(date) : date
    return new Intl.DateTimeFormat('en-US', options).format(dateObj)
  },

  // Relative time formatter
  relativeTime: (date: Date | string) => {
    const dateObj = typeof date === 'string' ? new Date(date) : date
    const now = new Date()
    const diff = now.getTime() - dateObj.getTime()

    const rtf = new Intl.RelativeTimeFormat('en-US', { numeric: 'auto' })

    const units = [
      { unit: 'year', ms: 1000 * 60 * 60 * 24 * 365 },
      { unit: 'month', ms: 1000 * 60 * 60 * 24 * 30 },
      { unit: 'day', ms: 1000 * 60 * 60 * 24 },
      { unit: 'hour', ms: 1000 * 60 * 60 },
      { unit: 'minute', ms: 1000 * 60 },
      { unit: 'second', ms: 1000 },
    ] as const

    for (const { unit, ms } of units) {
      if (Math.abs(diff) >= ms) {
        return rtf.format(-Math.round(diff / ms), unit)
      }
    }

    return rtf.format(0, 'second')
  },

  // File size formatter
  fileSize: (bytes: number) => {
    if (bytes === 0) return '0 Bytes'

    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))

    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  },

  // Percentage formatter
  percentage: (value: number, total: number) => {
    return ((value / total) * 100).toFixed(1) + '%'
  },
}

// String utilities
export const stringUtils = {
  // Capitalize first letter
  capitalize: (str: string) => {
    return str.charAt(0).toUpperCase() + str.slice(1).toLowerCase()
  },

  // Convert to title case
  titleCase: (str: string) => {
    return str
      .toLowerCase()
      .split(' ')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  },

  // Convert to slug
  slugify: (str: string) => {
    return str
      .toLowerCase()
      .trim()
      .replace(/[^\w\s-]/g, '')
      .replace(/[\s_-]+/g, '-')
      .replace(/^-+|-+$/g, '')
  },

  // Truncate string
  truncate: (str: string, length: number, suffix = '...') => {
    if (str.length <= length) return str
    return str.slice(0, length) + suffix
  },

  // Extract initials
  initials: (name: string) => {
    return name
      .split(' ')
      .map(part => part[0])
      .join('')
      .toUpperCase()
      .slice(0, 2)
  },

  // Generate random string
  random: (length: number) => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    let result = ''
    for (let i = 0; i < length; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return result
  },
}

// Array utilities
export const arrayUtils = {
  // Remove duplicates
  unique: <T>(arr: T[]) => [...new Set(arr)],

  // Chunk array
  chunk: <T>(arr: T[], size: number) => {
    const chunks: T[][] = []
    for (let i = 0; i < arr.length; i += size) {
      chunks.push(arr.slice(i, i + size))
    }
    return chunks
  },

  // Shuffle array
  shuffle: <T>(arr: T[]) => {
    const result = [...arr]
    for (let i = result.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      ;[result[i], result[j]] = [result[j], result[i]]
    }
    return result
  },

  // Group by key
  groupBy: <T>(arr: T[], key: keyof T) => {
    return arr.reduce((groups, item) => {
      const groupKey = item[key] as string
      if (!groups[groupKey]) {
        groups[groupKey] = []
      }
      groups[groupKey].push(item)
      return groups
    }, {} as Record<string, T[]>)
  },
}

// Object utilities
export const objectUtils = {
  // Pick keys from object
  pick: <T extends object, K extends keyof T>(obj: T, keys: K[]): Pick<T, K> => {
    const result = {} as Pick<T, K>
    keys.forEach(key => {
      if (key in obj) {
        result[key] = obj[key]
      }
    })
    return result
  },

  // Omit keys from object
  omit: <T extends object, K extends keyof T>(obj: T, keys: K[]): Omit<T, K> => {
    const result = { ...obj }
    keys.forEach(key => {
      delete result[key]
    })
    return result
  },

  // Deep merge objects
  deepMerge: <T extends object>(target: T, source: Partial<T>): T => {
    const result = { ...target }
    
    Object.keys(source).forEach(key => {
      const sourceValue = source[key as keyof T]
      const targetValue = result[key as keyof T]
      
      if (
        sourceValue &&
        typeof sourceValue === 'object' &&
        !Array.isArray(sourceValue) &&
        targetValue &&
        typeof targetValue === 'object' &&
        !Array.isArray(targetValue)
      ) {
        result[key as keyof T] = objectUtils.deepMerge(targetValue, sourceValue)
      } else if (sourceValue !== undefined) {
        result[key as keyof T] = sourceValue
      }
    })
    
    return result
  },
}

// URL utilities
export const urlUtils = {
  // Build URL with query params
  buildUrl: (base: string, params: Record<string, string | number | boolean>) => {
    const url = new URL(base, window.location.origin)
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        url.searchParams.set(key, String(value))
      }
    })
    return url.toString()
  },

  // Parse query string
  parseQuery: (search: string) => {
    const params = new URLSearchParams(search)
    const result: Record<string, string> = {}
    params.forEach((value, key) => {
      result[key] = value
    })
    return result
  },
}

// Validation utilities
export const validationUtils = {
  // Email validation
  isEmail: (email: string) => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailRegex.test(email)
  },

  // URL validation
  isUrl: (url: string) => {
    try {
      new URL(url)
      return true
    } catch {
      return false
    }
  },

  // Phone validation (basic)
  isPhone: (phone: string) => {
    const phoneRegex = /^\+?[\d\s\-\(\)]{10,}$/
    return phoneRegex.test(phone)
  },

  // Strong password validation
  isStrongPassword: (password: string) => {
    const minLength = 8
    const hasUpperCase = /[A-Z]/.test(password)
    const hasLowerCase = /[a-z]/.test(password)
    const hasNumbers = /\d/.test(password)
    const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password)

    return (
      password.length >= minLength &&
      hasUpperCase &&
      hasLowerCase &&
      hasNumbers &&
      hasSpecialChar
    )
  },
}

// Local storage utilities with error handling
export const storageUtils = {
  get: <T>(key: string, defaultValue?: T): T | null => {
    if (typeof window === 'undefined') return defaultValue ?? null

    try {
      const item = window.localStorage.getItem(key)
      return item ? JSON.parse(item) : defaultValue ?? null
    } catch (error) {
      console.error(`Error reading localStorage key "${key}":`, error)
      return defaultValue ?? null
    }
  },

  set: <T>(key: string, value: T): void => {
    if (typeof window === 'undefined') return

    try {
      window.localStorage.setItem(key, JSON.stringify(value))
    } catch (error) {
      console.error(`Error setting localStorage key "${key}":`, error)
    }
  },

  remove: (key: string): void => {
    if (typeof window === 'undefined') return

    try {
      window.localStorage.removeItem(key)
    } catch (error) {
      console.error(`Error removing localStorage key "${key}":`, error)
    }
  },

  clear: (): void => {
    if (typeof window === 'undefined') return

    try {
      window.localStorage.clear()
    } catch (error) {
      console.error('Error clearing localStorage:', error)
    }
  },
}

// Debounce utility
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: NodeJS.Timeout

  return (...args: Parameters<T>) => {
    clearTimeout(timeout)
    timeout = setTimeout(() => func(...args), wait)
  }
}

// Throttle utility
export function throttle<T extends (...args: any[]) => any>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle: boolean

  return (...args: Parameters<T>) => {
    if (!inThrottle) {
      func(...args)
      inThrottle = true
      setTimeout(() => (inThrottle = false), limit)
    }
  }
}

// Sleep utility
export const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))