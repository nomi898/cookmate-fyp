function requestLogger(req, res, next) {
    console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
    if (req.headers.authorization) {
      console.log('Auth header present');
    }
    next();
  }
  
  function structuredLogger(req, res, next) {
    const start = Date.now();
    res.on('finish', () => {
      const duration = Date.now() - start;
      console.log(JSON.stringify({
        timestamp: new Date().toISOString(),
        method: req.method,
        path: req.path,
        status: res.statusCode,
        duration: `${duration}ms`,
        userAgent: req.get('user-agent')
      }));
    });
    next();
  }
  
  module.exports = { requestLogger, structuredLogger };
  