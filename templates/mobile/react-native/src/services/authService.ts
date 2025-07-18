import { apiClient } from './apiClient'
import { User } from '../types/user'

export interface LoginCredentials {
  email: string
  password: string
}

export interface RegisterData {
  name: string
  email: string
  password: string
}

export interface AuthResponse {
  user: User
  token: string
  refreshToken?: string
}

export const authService = {
  async login(credentials: LoginCredentials): Promise<AuthResponse> {
    const response = await apiClient.post('/auth/login', credentials)
    return response.data
  },

  async register(userData: RegisterData): Promise<AuthResponse> {
    const response = await apiClient.post('/auth/register', userData)
    return response.data
  },

  async logout(): Promise<void> {
    await apiClient.post('/auth/logout')
  },

  async getCurrentUser(token: string): Promise<User> {
    const response = await apiClient.get('/auth/me', {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    })
    return response.data
  },

  async refreshToken(token: string): Promise<AuthResponse> {
    const response = await apiClient.post('/auth/refresh', {
      token,
    })
    return response.data
  },

  async forgotPassword(email: string): Promise<{ message: string }> {
    const response = await apiClient.post('/auth/forgot-password', { email })
    return response.data
  },

  async resetPassword(token: string, password: string): Promise<{ message: string }> {
    const response = await apiClient.post('/auth/reset-password', {
      token,
      password,
    })
    return response.data
  },

  async changePassword(currentPassword: string, newPassword: string): Promise<{ message: string }> {
    const response = await apiClient.post('/auth/change-password', {
      currentPassword,
      newPassword,
    })
    return response.data
  },

  async verifyEmail(token: string): Promise<{ message: string }> {
    const response = await apiClient.post('/auth/verify-email', { token })
    return response.data
  },

  async resendVerificationEmail(): Promise<{ message: string }> {
    const response = await apiClient.post('/auth/resend-verification')
    return response.data
  },

  async deleteAccount(password: string): Promise<{ message: string }> {
    const response = await apiClient.post('/auth/delete-account', { password })
    return response.data
  },
}