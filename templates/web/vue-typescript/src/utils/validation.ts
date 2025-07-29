import { z } from 'zod'

// Common validation schemas
export const validationSchemas = {
  // Email validation
  email: z
    .string()
    .min(1, 'Email is required')
    .email('Please enter a valid email address')
    .max(255, 'Email must be less than 255 characters'),

  // Password validation
  password: z
    .string()
    .min(8, 'Password must be at least 8 characters long')
    .max(128, 'Password must be less than 128 characters')
    .regex(
      /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/,
      'Password must contain at least one lowercase letter, one uppercase letter, and one number'
    ),

  // Name validation
  name: z
    .string()
    .min(1, 'Name is required')
    .max(100, 'Name must be less than 100 characters')
    .regex(/^[a-zA-Z\s'-]+$/, 'Name can only contain letters, spaces, hyphens, and apostrophes'),

  // URL validation
  url: z.string().url('Please enter a valid URL'),

  // Phone validation
  phone: z
    .string()
    .regex(/^[\+]?[0-9\s\-\(\)]{10,}$/, 'Please enter a valid phone number'),

  // Required string
  requiredString: z.string().min(1, 'This field is required'),

  // Optional string
  optionalString: z.string().optional(),
}

// Form validation schemas
export const formSchemas = {
  // Login form
  login: z.object({
    email: validationSchemas.email,
    password: z.string().min(1, 'Password is required'),
  }),

  // Registration form
  register: z
    .object({
      name: validationSchemas.name,
      email: validationSchemas.email,
      password: validationSchemas.password,
      confirmPassword: z.string(),
    })
    .refine((data) => data.password === data.confirmPassword, {
      message: 'Passwords do not match',
      path: ['confirmPassword'],
    }),

  // Profile update form
  profileUpdate: z.object({
    name: validationSchemas.name,
    email: validationSchemas.email,
  }),

  // Password change form
  passwordChange: z
    .object({
      currentPassword: z.string().min(1, 'Current password is required'),
      newPassword: validationSchemas.password,
      confirmPassword: z.string(),
    })
    .refine((data) => data.newPassword === data.confirmPassword, {
      message: 'Passwords do not match',
      path: ['confirmPassword'],
    }),

  // User creation form (admin)
  userCreate: z.object({
    name: validationSchemas.name,
    email: validationSchemas.email,
    password: validationSchemas.password,
    role: z.enum(['user', 'admin']).default('user'),
  }),

  // User update form (admin)
  userUpdate: z.object({
    name: validationSchemas.name.optional(),
    email: validationSchemas.email.optional(),
    role: z.enum(['user', 'admin']).optional(),
    isActive: z.boolean().optional(),
  }),

  // Contact form
  contact: z.object({
    name: validationSchemas.name,
    email: validationSchemas.email,
    subject: z.string().min(1, 'Subject is required').max(200, 'Subject is too long'),
    message: z
      .string()
      .min(10, 'Message must be at least 10 characters long')
      .max(1000, 'Message is too long'),
  }),

  // Settings form
  settings: z.object({
    theme: z.enum(['light', 'dark', 'auto']).default('auto'),
    language: z.string().min(1, 'Language is required'),
    timezone: z.string().min(1, 'Timezone is required'),
    emailNotifications: z.boolean().default(true),
    pushNotifications: z.boolean().default(false),
    profileVisible: z.boolean().default(true),
  }),
}

// Validation helper functions
export const validationHelpers = {
  // Validate a single field
  validateField<T>(schema: z.ZodType<T>, value: unknown): { success: boolean; error?: string } {
    try {
      schema.parse(value)
      return { success: true }
    } catch (error) {
      if (error instanceof z.ZodError) {
        return { success: false, error: error.errors[0]?.message }
      }
      return { success: false, error: 'Validation failed' }
    }
  },

  // Validate an entire form
  validateForm<T>(
    schema: z.ZodType<T>,
    data: Record<string, unknown>
  ): { success: boolean; data?: T; errors?: Record<string, string> } {
    try {
      const validData = schema.parse(data)
      return { success: true, data: validData }
    } catch (error) {
      if (error instanceof z.ZodError) {
        const errors: Record<string, string> = {}
        error.errors.forEach((err) => {
          const path = err.path.join('.')
          errors[path] = err.message
        })
        return { success: false, errors }
      }
      return { success: false, errors: { _form: 'Validation failed' } }
    }
  },

  // Check if email is valid
  isValidEmail(email: string): boolean {
    return validationSchemas.email.safeParse(email).success
  },

  // Check if password is strong
  isStrongPassword(password: string): boolean {
    return validationSchemas.password.safeParse(password).success
  },

  // Get password strength
  getPasswordStrength(password: string): {
    score: number
    feedback: string[]
    isValid: boolean
  } {
    const feedback: string[] = []
    let score = 0

    // Length check
    if (password.length < 8) {
      feedback.push('Password must be at least 8 characters long')
    } else if (password.length >= 8 && password.length < 12) {
      score += 1
    } else if (password.length >= 12) {
      score += 2
    }

    // Character variety checks
    const hasLowercase = /[a-z]/.test(password)
    const hasUppercase = /[A-Z]/.test(password)
    const hasNumbers = /\d/.test(password)
    const hasSymbols = /[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]/.test(password)

    if (!hasLowercase) feedback.push('Include lowercase letters')
    else score += 0.5

    if (!hasUppercase) feedback.push('Include uppercase letters')
    else score += 0.5

    if (!hasNumbers) feedback.push('Include numbers')
    else score += 0.5

    if (!hasSymbols) feedback.push('Include special characters')
    else score += 0.5

    // Common patterns check
    const commonPatterns = [
      /(.)\1{2,}/, // Repeated characters
      /123456|654321|abcdef|qwerty|password/i, // Common sequences
    ]

    for (const pattern of commonPatterns) {
      if (pattern.test(password)) {
        feedback.push('Avoid common patterns and repeated characters')
        score -= 1
        break
      }
    }

    // Normalize score to 0-5 range
    score = Math.max(0, Math.min(5, Math.round(score)))

    const isValid = score >= 3 && feedback.length === 0

    return { score, feedback, isValid }
  },

  // Sanitize input string
  sanitizeInput(input: string): string {
    return input
      .trim()
      .replace(/[<>]/g, '') // Remove potential HTML tags
      .replace(/['"]/g, '') // Remove quotes
  },

  // Validate file upload
  validateFile(
    file: File,
    options: {
      maxSize?: number // in bytes
      allowedTypes?: string[]
      allowedExtensions?: string[]
    } = {}
  ): { success: boolean; error?: string } {
    const { maxSize = 10 * 1024 * 1024, allowedTypes = [], allowedExtensions = [] } = options

    // Check file size
    if (file.size > maxSize) {
      const maxSizeMB = Math.round(maxSize / (1024 * 1024))
      return { success: false, error: `File size must be less than ${maxSizeMB}MB` }
    }

    // Check file type
    if (allowedTypes.length > 0 && !allowedTypes.includes(file.type)) {
      return { success: false, error: `File type ${file.type} is not allowed` }
    }

    // Check file extension
    if (allowedExtensions.length > 0) {
      const extension = file.name.split('.').pop()?.toLowerCase()
      if (!extension || !allowedExtensions.includes(extension)) {
        return {
          success: false,
          error: `File extension must be one of: ${allowedExtensions.join(', ')}`,
        }
      }
    }

    return { success: true }
  },
}

export default validationHelpers