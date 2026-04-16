/**
 * Tests for configuration loader.
 */

const { ConfigLoader, ConfigValidationError, Config, DatabaseConfig, RedisConfig } = require('./loader');

describe('ConfigLoader', () => {
  const originalEnv = process.env;
  
  beforeEach(() => {
    process.env = { ...originalEnv };
  });
  
  afterEach(() => {
    process.env = originalEnv;
  });
  
  describe('load', () => {
    test('should load local configuration', async () => {
      process.env.APP_ENV = 'local';
      process.env.DATABASE_HOST = 'localhost';
      process.env.DATABASE_NAME = 'testdb';
      process.env.DATABASE_PASSWORD = 'testpass';
      process.env.REDIS_HOST = 'localhost';
      
      const loader = new ConfigLoader();
      const config = await loader.load();
      
      expect(config.app.env).toBe('local');
      expect(config.database.host).toBe('localhost');
      expect(config.database.name).toBe('testdb');
      expect(config.redis.host).toBe('localhost');
    });
    
    test('should fail validation for missing required fields', async () => {
      process.env.APP_ENV = 'local';
      delete process.env.DATABASE_HOST;
      
      const loader = new ConfigLoader();
      
      await expect(loader.load()).rejects.toThrow(ConfigValidationError);
    });
    
    test('should override config with env vars', async () => {
      process.env.APP_ENV = 'local';
      process.env.DATABASE_HOST = 'localhost';
      process.env.DATABASE_NAME = 'testdb';
      process.env.DATABASE_PASSWORD = 'testpass';
      process.env.REDIS_HOST = 'localhost';
      process.env.LOG_LEVEL = 'debug';
      process.env.DATABASE_PORT = '5433';
      
      const loader = new ConfigLoader();
      const config = await loader.load();
      
      expect(config.app.logLevel).toBe('debug');
      expect(config.database.port).toBe(5433);
    });
    
    test('should fail for invalid SSL mode', async () => {
      process.env.APP_ENV = 'local';
      process.env.DATABASE_HOST = 'localhost';
      process.env.DATABASE_NAME = 'testdb';
      process.env.DATABASE_PASSWORD = 'testpass';
      process.env.REDIS_HOST = 'localhost';
      process.env.DATABASE_SSL_MODE = 'invalid';
      
      const loader = new ConfigLoader();
      
      await expect(loader.load()).rejects.toThrow('sslMode');
    });
  });
  
  describe('getDSN', () => {
    test('should generate correct DSN', () => {
      const config = new Config({
        database: {
          host: 'localhost',
          port: 5432,
          user: 'testuser',
          password: 'testpass',
          name: 'testdb',
          sslMode: 'require',
        },
      });
      
      const loader = new ConfigLoader();
      const dsn = loader.getDSN(config);
      
      expect(dsn).toContain('host=localhost');
      expect(dsn).toContain('port=5432');
      expect(dsn).toContain('user=testuser');
      expect(dsn).toContain('dbname=testdb');
      expect(dsn).toContain('sslmode=require');
    });
  });
  
  describe('getRedisURL', () => {
    test('should generate correct Redis URL with password', () => {
      const config = new Config({
        redis: {
          host: 'localhost',
          port: 6379,
          password: 'redispass',
          db: 0,
        },
      });
      
      const loader = new ConfigLoader();
      const url = loader.getRedisURL(config);
      
      expect(url).toBe('redis://:redispass@localhost:6379/0');
    });
    
    test('should generate correct Redis URL without password', () => {
      const config = new Config({
        redis: {
          host: 'localhost',
          port: 6379,
          db: 0,
        },
      });
      
      const loader = new ConfigLoader();
      const url = loader.getRedisURL(config);
      
      expect(url).toBe('redis://localhost:6379/0');
    });
  });
});
