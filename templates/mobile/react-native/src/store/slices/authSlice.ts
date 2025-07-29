import { createSlice, createAsyncThunk, PayloadAction } from '@reduxjs/toolkit'
import * as SecureStore from 'expo-secure-store'

import { authService } from '../../services/authService'
import { User } from '../../types/user'

interface AuthState {
  user: User | null
  token: string | null
  isAuthenticated: boolean
  isLoading: boolean
  error: string | null
}

const initialState: AuthState = {
  user: null,
  token: null,
  isAuthenticated: false,
  isLoading: false,
  error: null,
}

// Async thunks
export const loginAsync = createAsyncThunk(
  'auth/login',
  async (credentials: { email: string; password: string }, { rejectWithValue }) => {
    try {
      const response = await authService.login(credentials)
      
      // Store token securely
      await SecureStore.setItemAsync('authToken', response.token)
      
      return response
    } catch (error: any) {
      return rejectWithValue(error.message || 'Login failed')
    }
  }
)

export const registerAsync = createAsyncThunk(
  'auth/register',
  async (userData: { name: string; email: string; password: string }, { rejectWithValue }) => {
    try {
      const response = await authService.register(userData)
      
      // Store token securely
      await SecureStore.setItemAsync('authToken', response.token)
      
      return response
    } catch (error: any) {
      return rejectWithValue(error.message || 'Registration failed')
    }
  }
)

export const logoutAsync = createAsyncThunk(
  'auth/logout',
  async (_, { rejectWithValue }) => {
    try {
      await authService.logout()
      
      // Remove token from secure storage
      await SecureStore.deleteItemAsync('authToken')
      
      return true
    } catch (error: any) {
      return rejectWithValue(error.message || 'Logout failed')
    }
  }
)

export const checkAuthStatusAsync = createAsyncThunk(
  'auth/checkStatus',
  async (_, { rejectWithValue }) => {
    try {
      const token = await SecureStore.getItemAsync('authToken')
      
      if (!token) {
        throw new Error('No token found')
      }
      
      const user = await authService.getCurrentUser(token)
      
      return { user, token }
    } catch (error: any) {
      // Remove invalid token
      await SecureStore.deleteItemAsync('authToken')
      return rejectWithValue(error.message || 'Authentication check failed')
    }
  }
)

export const refreshTokenAsync = createAsyncThunk(
  'auth/refreshToken',
  async (_, { rejectWithValue }) => {
    try {
      const currentToken = await SecureStore.getItemAsync('authToken')
      
      if (!currentToken) {
        throw new Error('No token to refresh')
      }
      
      const response = await authService.refreshToken(currentToken)
      
      // Store new token
      await SecureStore.setItemAsync('authToken', response.token)
      
      return response
    } catch (error: any) {
      // Remove invalid token
      await SecureStore.deleteItemAsync('authToken')
      return rejectWithValue(error.message || 'Token refresh failed')
    }
  }
)

const authSlice = createSlice({
  name: 'auth',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null
    },
    setLoading: (state, action: PayloadAction<boolean>) => {
      state.isLoading = action.payload
    },
    updateUser: (state, action: PayloadAction<Partial<User>>) => {
      if (state.user) {
        state.user = { ...state.user, ...action.payload }
      }
    },
  },
  extraReducers: (builder) => {
    // Login
    builder
      .addCase(loginAsync.pending, (state) => {
        state.isLoading = true
        state.error = null
      })
      .addCase(loginAsync.fulfilled, (state, action) => {
        state.isLoading = false
        state.user = action.payload.user
        state.token = action.payload.token
        state.isAuthenticated = true
        state.error = null
      })
      .addCase(loginAsync.rejected, (state, action) => {
        state.isLoading = false
        state.error = action.payload as string
        state.isAuthenticated = false
      })

    // Register
    builder
      .addCase(registerAsync.pending, (state) => {
        state.isLoading = true
        state.error = null
      })
      .addCase(registerAsync.fulfilled, (state, action) => {
        state.isLoading = false
        state.user = action.payload.user
        state.token = action.payload.token
        state.isAuthenticated = true
        state.error = null
      })
      .addCase(registerAsync.rejected, (state, action) => {
        state.isLoading = false
        state.error = action.payload as string
        state.isAuthenticated = false
      })

    // Logout
    builder
      .addCase(logoutAsync.pending, (state) => {
        state.isLoading = true
      })
      .addCase(logoutAsync.fulfilled, (state) => {
        state.isLoading = false
        state.user = null
        state.token = null
        state.isAuthenticated = false
        state.error = null
      })
      .addCase(logoutAsync.rejected, (state, action) => {
        state.isLoading = false
        state.error = action.payload as string
        // Still logout on error
        state.user = null
        state.token = null
        state.isAuthenticated = false
      })

    // Check auth status
    builder
      .addCase(checkAuthStatusAsync.pending, (state) => {
        state.isLoading = true
      })
      .addCase(checkAuthStatusAsync.fulfilled, (state, action) => {
        state.isLoading = false
        state.user = action.payload.user
        state.token = action.payload.token
        state.isAuthenticated = true
        state.error = null
      })
      .addCase(checkAuthStatusAsync.rejected, (state) => {
        state.isLoading = false
        state.user = null
        state.token = null
        state.isAuthenticated = false
        state.error = null // Don't show error for failed auth check
      })

    // Refresh token
    builder
      .addCase(refreshTokenAsync.fulfilled, (state, action) => {
        state.token = action.payload.token
        state.user = action.payload.user
      })
      .addCase(refreshTokenAsync.rejected, (state) => {
        state.user = null
        state.token = null
        state.isAuthenticated = false
      })
  },
})

export const { clearError, setLoading, updateUser } = authSlice.actions

export default authSlice.reducer