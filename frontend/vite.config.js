import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 모바일 세로 화면 기준 PoC. 개발 서버 5173.
export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    // FastAPI(8000)로 커스텀 로직 호출 시 프록시 (AI 분담·알림톡)
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
})
