import { ref, reactive, computed } from 'vue'
import { api, apiHelpers } from '@/utils/api'
import type { ApiResponse } from '@/types'

export interface UseApiOptions {
  immediate?: boolean
  onError?: (error: any) => void
  onSuccess?: (data: any) => void
  transform?: (data: any) => any
}

export function useApi<T = any>(
  url: string,
  options: UseApiOptions = {}
) {
  const { immediate = false, onError, onSuccess, transform } = options

  // State
  const data = ref<T | null>(null)
  const error = ref<string | null>(null)
  const isLoading = ref(false)
  const isError = computed(() => !!error.value)
  const isSuccess = computed(() => !!data.value && !error.value)

  // Execute the request
  async function execute(config?: any): Promise<T | null> {
    try {
      isLoading.value = true
      error.value = null

      const response = await api.get(url, config)
      const responseData = response.data.data

      // Transform data if transform function is provided
      const finalData = transform ? transform(responseData) : responseData
      data.value = finalData

      onSuccess?.(finalData)
      return finalData
    } catch (err: any) {
      const errorMessage = err.response?.data?.message || err.message || 'An error occurred'
      error.value = errorMessage
      onError?.(err)
      return null
    } finally {
      isLoading.value = false
    }
  }

  // Refresh the data
  async function refresh(): Promise<T | null> {
    return execute()
  }

  // Execute immediately if requested
  if (immediate) {
    execute()
  }

  return {
    data,
    error,
    isLoading,
    isError,
    isSuccess,
    execute,
    refresh,
  }
}

export function useApiMutation<TData = any, TVariables = any>(
  mutationFn: (variables: TVariables) => Promise<ApiResponse<TData>>,
  options: {
    onSuccess?: (data: TData, variables: TVariables) => void
    onError?: (error: any, variables: TVariables) => void
  } = {}
) {
  const { onSuccess, onError } = options

  // State
  const data = ref<TData | null>(null)
  const error = ref<string | null>(null)
  const isLoading = ref(false)
  const isError = computed(() => !!error.value)
  const isSuccess = computed(() => !!data.value && !error.value)

  // Execute the mutation
  async function mutate(variables: TVariables): Promise<TData | null> {
    try {
      isLoading.value = true
      error.value = null

      const response = await mutationFn(variables)
      data.value = response.data

      onSuccess?.(response.data, variables)
      return response.data
    } catch (err: any) {
      const errorMessage = err.response?.data?.message || err.message || 'An error occurred'
      error.value = errorMessage
      onError?.(err, variables)
      return null
    } finally {
      isLoading.value = false
    }
  }

  // Reset the mutation state
  function reset(): void {
    data.value = null
    error.value = null
    isLoading.value = false
  }

  return {
    data,
    error,
    isLoading,
    isError,
    isSuccess,
    mutate,
    reset,
  }
}

// Specialized hooks for common API operations
export function useApiQuery<T = any>(url: string, options: UseApiOptions = {}) {
  return useApi<T>(url, { immediate: true, ...options })
}

export function useApiPost<TData = any, TVariables = any>(
  url: string,
  options: {
    onSuccess?: (data: TData, variables: TVariables) => void
    onError?: (error: any, variables: TVariables) => void
  } = {}
) {
  return useApiMutation<TData, TVariables>(
    (variables) => apiHelpers.post(url, variables),
    options
  )
}

export function useApiPut<TData = any, TVariables = any>(
  url: string,
  options: {
    onSuccess?: (data: TData, variables: TVariables) => void
    onError?: (error: any, variables: TVariables) => void
  } = {}
) {
  return useApiMutation<TData, TVariables>(
    (variables) => apiHelpers.put(url, variables),
    options
  )
}

export function useApiDelete<TData = any>(
  url: string,
  options: {
    onSuccess?: (data: TData) => void
    onError?: (error: any) => void
  } = {}
) {
  return useApiMutation<TData, void>(
    () => apiHelpers.delete(url),
    {
      onSuccess: (data) => options.onSuccess?.(data),
      onError: (error) => options.onError?.(error),
    }
  )
}

// Infinite query for pagination
export function useInfiniteQuery<T = any>(
  baseUrl: string,
  options: {
    pageSize?: number
    getNextPageParam?: (lastPage: any, allPages: any[]) => any
    onError?: (error: any) => void
  } = {}
) {
  const { pageSize = 10, getNextPageParam, onError } = options

  // State
  const pages = ref<T[][]>([])
  const isLoading = ref(false)
  const isLoadingMore = ref(false)
  const error = ref<string | null>(null)
  const hasNextPage = ref(true)

  // Computed
  const data = computed(() => pages.value.flat())
  const isError = computed(() => !!error.value)

  // Fetch first page
  async function fetchFirstPage(): Promise<void> {
    try {
      isLoading.value = true
      error.value = null

      const response = await api.get(baseUrl, {
        params: { page: 1, limit: pageSize },
      })

      const pageData = response.data.data
      const meta = response.data.meta

      pages.value = [pageData]
      hasNextPage.value = meta.page < meta.totalPages
    } catch (err: any) {
      const errorMessage = err.response?.data?.message || err.message || 'An error occurred'
      error.value = errorMessage
      onError?.(err)
    } finally {
      isLoading.value = false
    }
  }

  // Fetch next page
  async function fetchNextPage(): Promise<void> {
    if (!hasNextPage.value || isLoadingMore.value) {
      return
    }

    try {
      isLoadingMore.value = true
      error.value = null

      const nextPage = pages.value.length + 1
      const response = await api.get(baseUrl, {
        params: { page: nextPage, limit: pageSize },
      })

      const pageData = response.data.data
      const meta = response.data.meta

      pages.value.push(pageData)
      hasNextPage.value = meta.page < meta.totalPages
    } catch (err: any) {
      const errorMessage = err.response?.data?.message || err.message || 'An error occurred'
      error.value = errorMessage
      onError?.(err)
    } finally {
      isLoadingMore.value = false
    }
  }

  // Refresh all data
  async function refresh(): Promise<void> {
    pages.value = []
    hasNextPage.value = true
    await fetchFirstPage()
  }

  return {
    data,
    pages,
    isLoading,
    isLoadingMore,
    error,
    isError,
    hasNextPage,
    fetchFirstPage,
    fetchNextPage,
    refresh,
  }
}