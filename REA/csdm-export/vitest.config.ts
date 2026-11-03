import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    // Test files share one throwaway PostgreSQL database (drop/recreate per
    // file); parallel execution would race on it.
    fileParallelism: false,
  },
});
