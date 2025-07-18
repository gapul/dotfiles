import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from 'axios'
import * as SecureStore from 'expo-secure-store'
import Constants from 'expo-constants'

import { store } from '../store'
import { refreshTokenAsync } from '../store/slices/authSlice'

// API configuration
const API_BASE_URL = Constants.expoConfig?.extra?.apiUrl || 'http://localhost:3000'
const API_TIMEOUT = 10000

// Create axios instance
export const apiClient: AxiosInstance = axios.create({
  baseURL: `${API_BASE_URL}/api`,
  timeout: API_TIMEOUT,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Request interceptor to add auth token
apiClient.interceptors.request.use(
  async (config: AxiosRequestConfig) => {
    const token = await SecureStore.getItemAsync('authToken')
    
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`
    }
    
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// Response interceptor for token refresh
apiClient.interceptors.response.use(
  (response: AxiosResponse) => {
    return response
  },
  async (error) => {
    const originalRequest = error.config
    
    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true
      
      try {
        // Attempt to refresh token
        await store.dispatch(refreshTokenAsync())
        
        // Retry original request with new token
        const newToken = await SecureStore.getItemAsync('authToken')
        if (newToken && originalRequest.headers) {
          originalRequest.headers.Authorization = `Bearer ${newToken}`
        }
        
        return apiClient(originalRequest)
      } catch (refreshError) {
        // Refresh failed, redirect to login
        // This will be handled by the auth slice
        return Promise.reject(refreshError)
      }
    }
    
    return Promise.reject(error)
  }
)

// API utility functions
export const apiUtils = {
  // Upload file with progress
  uploadFile: async (
    url: string,
    file: FormData,
    onProgress?: (progress: number) => void
  ) => {
    return apiClient.post(url, file, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      onUploadProgress: (progressEvent) => {
        if (onProgress && progressEvent.total) {
          const progress = Math.round((progressEvent.loaded * 100) / progressEvent.total)
          onProgress(progress)
        }
      },
    })
  },

  // Download file
  downloadFile: async (url: string, filename: string) => {
    const response = await apiClient.get(url, {
      responseType: 'blob',
    })
    
    // Create blob URL and trigger download
    const blob = new Blob([response.data])
    const blobUrl = URL.createObjectURL(blob)
    
    // For React Native, you would handle file saving differently
    // This is more for web compatibility
    return blobUrl
  },

  // Health check
  healthCheck: async () => {
    try {
      const response = await apiClient.get('/health')
      return response.data
    } catch (error) {
      throw new Error('API health check failed')
    }
  },
}

export default apiClient