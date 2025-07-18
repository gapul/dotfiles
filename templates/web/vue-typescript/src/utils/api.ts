import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from 'axios'
import type { ApiResponse, ErrorResponse } from '@/types'

// Create axios instance
export const api: AxiosInstance = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:3000/api',
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Request interceptor
api.interceptors.request.use(
  (config) => {
    // Add auth token if available
    const token = localStorage.getItem('auth_token')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }

    // Add request timestamp for debugging
    config.metadata = { startTime: new Date().getTime() }

    console.log(`[API] ${config.method?.toUpperCase()} ${config.url}`, {
      params: config.params,
      data: config.data,
    })

    return config
  },
  (error) => {
    console.error('[API] Request error:', error)
    return Promise.reject(error)
  }
)

// Response interceptor
api.interceptors.response.use(
  (response: AxiosResponse) => {
    // Calculate request duration
    const duration = new Date().getTime() - response.config.metadata?.startTime
    
    console.log(`[API] ${response.status} ${response.config.method?.toUpperCase()} ${response.config.url} (${duration}ms)`, {
      data: response.data,
    })

    return response
  },
  async (error) => {
    const duration = error.config?.metadata?.startTime
      ? new Date().getTime() - error.config.metadata.startTime
      : 0

    console.error(`[API] ${error.response?.status || 'ERROR'} ${error.config?.method?.toUpperCase()} ${error.config?.url} (${duration}ms)`, {
      error: error.response?.data || error.message,
    })

    // Handle 401 Unauthorized
    if (error.response?.status === 401) {
      // Try to refresh token
      const refreshToken = localStorage.getItem('refresh_token')
      if (refreshToken && !error.config._retry) {
        error.config._retry = true
        
        try {
          const response = await api.post('/auth/refresh', { refreshToken })
          const { token } = response.data.data
          
          localStorage.setItem('auth_token', token)
          error.config.headers.Authorization = `Bearer ${token}`
          
          return api.request(error.config)
        } catch (refreshError) {
          // Refresh failed, redirect to login
          localStorage.removeItem('auth_token')
          localStorage.removeItem('refresh_token')
          localStorage.removeItem('auth_user')
          
          if (window.location.pathname !== '/login') {
            window.location.href = '/login'
          }
        }
      } else {
        // No refresh token or refresh already tried, redirect to login
        localStorage.removeItem('auth_token')
        localStorage.removeItem('refresh_token')
        localStorage.removeItem('auth_user')
        
        if (window.location.pathname !== '/login') {
          window.location.href = '/login'
        }
      }
    }

    // Handle network errors
    if (!error.response) {
      error.response = {
        data: {
          success: false,
          error: 'Network Error',
          message: 'Unable to connect to the server. Please check your internet connection.',
          statusCode: 0,
          timestamp: new Date().toISOString(),
          path: error.config?.url || '',
        } as ErrorResponse,
        status: 0,
        statusText: 'Network Error',
      }
    }

    return Promise.reject(error)
  }
)

// API helper functions
export const apiHelpers = {
  // GET request with typed response
  async get<T = any>(url: string, config?: AxiosRequestConfig): Promise<ApiResponse<T>> {
    const response = await api.get(url, config)
    return response.data
  },

  // POST request with typed response
  async post<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<ApiResponse<T>> {
    const response = await api.post(url, data, config)
    return response.data
  },

  // PUT request with typed response
  async put<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<ApiResponse<T>> {
    const response = await api.put(url, data, config)
    return response.data
  },

  // PATCH request with typed response
  async patch<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<ApiResponse<T>> {
    const response = await api.patch(url, data, config)
    return response.data
  },

  // DELETE request with typed response
  async delete<T = any>(url: string, config?: AxiosRequestConfig): Promise<ApiResponse<T>> {
    const response = await api.delete(url, config)
    return response.data
  },

  // Upload file with progress
  async uploadFile(
    url: string,
    file: File,
    onProgress?: (progress: number) => void
  ): Promise<ApiResponse> {
    const formData = new FormData()
    formData.append('file', file)

    const response = await api.post(url, formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      onUploadProgress: (progressEvent) => {
        if (onProgress && progressEvent.total) {
          const progress = Math.round((progressEvent.loaded / progressEvent.total) * 100)
          onProgress(progress)
        }
      },
    })

    return response.data
  },

  // Download file
  async downloadFile(url: string, filename?: string): Promise<void> {
    const response = await api.get(url, {
      responseType: 'blob',
    })

    const blob = new Blob([response.data])
    const downloadUrl = window.URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = downloadUrl
    link.download = filename || 'download'
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    window.URL.revokeObjectURL(downloadUrl)
  },
}

// Export default instance
export default api

// Type declaration for axios config metadata
declare module 'axios' {
  interface AxiosRequestConfig {
    metadata?: {
      startTime: number
    }
    _retry?: boolean
  }
}