function errorHandler(err, req, res, next) {
    const errorResponse = {
      message: err.message || 'Internal server error',
      status: err.status || 500,
      path: req.path,
      timestamp: new Date().toISOString()
    };
    console.error(JSON.stringify(errorResponse));
    res.status(errorResponse.status).json({
      message: errorResponse.message
    });
  }
  
  module.exports = errorHandler;
  