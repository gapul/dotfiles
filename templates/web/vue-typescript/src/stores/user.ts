import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { User, PaginatedResponse } from '@/types'
import { api } from '@/utils/api'
import { useNotificationStore } from './notification'

export const useUserStore = defineStore('user', () => {
  // State
  const users = ref<User[]>([])
  const currentUser = ref<User | null>(null)
  const isLoading = ref(false)
  const pagination = ref({
    page: 1,
    limit: 10,
    total: 0,
    totalPages: 0,
  })
  const filters = ref({
    search: '',
    role: '',
    isActive: '',
    sortBy: 'createdAt',
    sortOrder: 'desc' as 'asc' | 'desc',
  })

  // Getters
  const hasUsers = computed(() => users.value.length > 0)
  const totalUsers = computed(() => pagination.value.total)
  const hasNextPage = computed(() => pagination.value.page < pagination.value.totalPages)
  const hasPrevPage = computed(() => pagination.value.page > 1)

  // Actions
  async function fetchUsers(page = 1): Promise<void> {
    try {
      isLoading.value = true
      
      const params = {
        page,
        limit: pagination.value.limit,
        ...filters.value,
      }
      
      const response = await api.get('/users', { params })
      const data: PaginatedResponse<User> = response.data
      
      users.value = data.data
      pagination.value = data.meta
      
    } catch (error: any) {
      const notificationStore = useNotificationStore()
      notificationStore.addNotification({
        type: 'error',
        title: 'Failed to fetch users',
        message: error.response?.data?.message || 'An error occurred',
      })
    } finally {
      isLoading.value = false
    }
  }

  async function fetchUser(id: string): Promise<User | null> {
    try {
      isLoading.value = true
      
      const response = await api.get(`/users/${id}`)
      const user: User = response.data.data
      
      currentUser.value = user
      return user
      
    } catch (error: any) {
      const notificationStore = useNotificationStore()
      notificationStore.addNotification({
        type: 'error',
        title: 'Failed to fetch user',
        message: error.response?.data?.message || 'User not found',
      })
      return null
    } finally {
      isLoading.value = false
    }
  }

  async function createUser(userData: Omit<User, 'id' | 'createdAt' | 'updatedAt'>): Promise<boolean> {
    const notificationStore = useNotificationStore()
    
    try {
      isLoading.value = true
      
      const response = await api.post('/users', userData)
      const newUser: User = response.data.data
      
      // Add to beginning of list
      users.value.unshift(newUser)
      
      notificationStore.addNotification({
        type: 'success',
        title: 'User created',
        message: `User ${newUser.name} has been created successfully.`,
      })
      
      return true
    } catch (error: any) {
      const message = error.response?.data?.message || 'Failed to create user'
      notificationStore.addNotification({
        type: 'error',
        title: 'Creation failed',
        message,
      })
      return false
    } finally {
      isLoading.value = false
    }
  }

  async function updateUser(id: string, userData: Partial<User>): Promise<boolean> {
    const notificationStore = useNotificationStore()
    
    try {
      isLoading.value = true
      
      const response = await api.put(`/users/${id}`, userData)
      const updatedUser: User = response.data.data
      
      // Update in list
      const index = users.value.findIndex(user => user.id === id)
      if (index !== -1) {
        users.value[index] = updatedUser
      }
      
      // Update current user if it's the same
      if (currentUser.value?.id === id) {
        currentUser.value = updatedUser
      }
      
      notificationStore.addNotification({
        type: 'success',
        title: 'User updated',
        message: `User ${updatedUser.name} has been updated successfully.`,
      })
      
      return true
    } catch (error: any) {
      const message = error.response?.data?.message || 'Failed to update user'
      notificationStore.addNotification({
        type: 'error',
        title: 'Update failed',
        message,
      })
      return false
    } finally {
      isLoading.value = false
    }
  }

  async function deleteUser(id: string): Promise<boolean> {
    const notificationStore = useNotificationStore()
    
    try {
      isLoading.value = true
      
      await api.delete(`/users/${id}`)
      
      // Remove from list
      users.value = users.value.filter(user => user.id !== id)
      
      // Clear current user if it's the deleted one
      if (currentUser.value?.id === id) {
        currentUser.value = null
      }
      
      notificationStore.addNotification({
        type: 'success',
        title: 'User deleted',
        message: 'User has been deleted successfully.',
      })
      
      return true
    } catch (error: any) {
      const message = error.response?.data?.message || 'Failed to delete user'
      notificationStore.addNotification({
        type: 'error',
        title: 'Deletion failed',
        message,
      })
      return false
    } finally {
      isLoading.value = false
    }
  }

  async function toggleUserStatus(id: string, isActive: boolean): Promise<boolean> {
    const notificationStore = useNotificationStore()
    
    try {
      isLoading.value = true
      
      const endpoint = isActive ? 'activate' : 'deactivate'
      await api.patch(`/users/${id}/${endpoint}`)
      
      // Update in list
      const index = users.value.findIndex(user => user.id === id)
      if (index !== -1) {
        users.value[index].isActive = isActive
      }
      
      // Update current user if it's the same
      if (currentUser.value?.id === id) {
        currentUser.value.isActive = isActive
      }
      
      const action = isActive ? 'activated' : 'deactivated'
      notificationStore.addNotification({
        type: 'success',
        title: `User ${action}`,
        message: `User has been ${action} successfully.`,
      })
      
      return true
    } catch (error: any) {
      const message = error.response?.data?.message || 'Failed to update user status'
      notificationStore.addNotification({
        type: 'error',
        title: 'Status update failed',
        message,
      })
      return false
    } finally {
      isLoading.value = false
    }
  }

  function setFilter(key: keyof typeof filters.value, value: string): void {
    filters.value[key] = value
    // Reset to first page when filters change
    if (key !== 'sortBy' && key !== 'sortOrder') {
      pagination.value.page = 1
    }
  }

  function setSort(sortBy: string, sortOrder: 'asc' | 'desc' = 'desc'): void {
    filters.value.sortBy = sortBy
    filters.value.sortOrder = sortOrder
  }

  function clearFilters(): void {
    filters.value = {
      search: '',
      role: '',
      isActive: '',
      sortBy: 'createdAt',
      sortOrder: 'desc',
    }
    pagination.value.page = 1
  }

  function nextPage(): void {
    if (hasNextPage.value) {
      pagination.value.page++
    }
  }

  function prevPage(): void {
    if (hasPrevPage.value) {
      pagination.value.page--
    }
  }

  function goToPage(page: number): void {
    if (page >= 1 && page <= pagination.value.totalPages) {
      pagination.value.page = page
    }
  }

  function setPageSize(limit: number): void {
    pagination.value.limit = limit
    pagination.value.page = 1 // Reset to first page
  }

  // Search users
  async function searchUsers(query: string): Promise<User[]> {
    try {
      const response = await api.get('/users/search', {
        params: { q: query, limit: 20 }
      })
      return response.data.data
    } catch (error) {
      console.error('Search failed:', error)
      return []
    }
  }

  // Get user statistics
  async function getUserStats(): Promise<{
    total: number
    active: number
    inactive: number
    admins: number
    users: number
    recentlyRegistered: number
  }> {
    try {
      const response = await api.get('/users/stats')
      return response.data.data
    } catch (error) {
      console.error('Failed to fetch user stats:', error)
      return {
        total: 0,
        active: 0,
        inactive: 0,
        admins: 0,
        users: 0,
        recentlyRegistered: 0,
      }
    }
  }

  return {
    // State
    users,
    currentUser,
    isLoading,
    pagination,
    filters,
    
    // Getters
    hasUsers,
    totalUsers,
    hasNextPage,
    hasPrevPage,
    
    // Actions
    fetchUsers,
    fetchUser,
    createUser,
    updateUser,
    deleteUser,
    toggleUserStatus,
    setFilter,
    setSort,
    clearFilters,
    nextPage,
    prevPage,
    goToPage,
    setPageSize,
    searchUsers,
    getUserStats,
  }
})