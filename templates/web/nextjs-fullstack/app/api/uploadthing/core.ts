import { createUploadthing, type FileRouter } from 'uploadthing/next'
import { getServerSession } from 'next-auth'

import { authOptions } from '@/lib/auth'

const f = createUploadthing()

// FileRouter for your app, can contain multiple FileRoutes
export const ourFileRouter = {
  // Define as many FileRoutes as you like, each with a unique routeSlug
  profileImage: f({ image: { maxFileSize: '4MB', maxFileCount: 1 } })
    // Set permissions and file types for this FileRoute
    .middleware(async ({ req }) => {
      // This code runs on your server before upload
      const session = await getServerSession(authOptions)

      // If you throw, the user will not be able to upload
      if (!session?.user) throw new Error('Unauthorized')

      // Whatever is returned here is accessible in onUploadComplete as `metadata`
      return { userId: session.user.id }
    })
    .onUploadComplete(async ({ metadata, file }) => {
      // This code RUNS ON YOUR SERVER after upload
      console.log('Upload complete for userId:', metadata.userId)

      console.log('file url', file.url)

      // !!! Whatever is returned here is sent to the clientside `onClientUploadComplete` callback
      return { uploadedBy: metadata.userId, url: file.url }
    }),
    
  postImage: f({ image: { maxFileSize: '8MB', maxFileCount: 5 } })
    .middleware(async ({ req }) => {
      const session = await getServerSession(authOptions)
      if (!session?.user) throw new Error('Unauthorized')
      return { userId: session.user.id }
    })
    .onUploadComplete(async ({ metadata, file }) => {
      console.log('Post image upload complete for userId:', metadata.userId)
      console.log('file url', file.url)
      return { uploadedBy: metadata.userId, url: file.url }
    }),
    
  documentUpload: f({ 
    image: { maxFileSize: '4MB' },
    pdf: { maxFileSize: '16MB' },
    text: { maxFileSize: '64KB' },
  })
    .middleware(async ({ req }) => {
      const session = await getServerSession(authOptions)
      if (!session?.user) throw new Error('Unauthorized')
      return { userId: session.user.id }
    })
    .onUploadComplete(async ({ metadata, file }) => {
      console.log('Document upload complete for userId:', metadata.userId)
      console.log('file url', file.url)
      return { uploadedBy: metadata.userId, url: file.url }
    }),
} satisfies FileRouter

export type OurFileRouter = typeof ourFileRouter