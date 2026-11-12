export async function healthRoutes(fastify, options) {
  fastify.get('/health', async (req, reply) => {
    return {
      status: 'ok',
      service: 'homespace',
      version: '1.0.0',
      serverTime: new Date().toISOString(),
    };
  });
}
