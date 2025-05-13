// voya-monorepo/apps/api/src/app.module.ts
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { TypeOrmModule, TypeOrmModuleOptions } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { Message } from './messages/message.entity';
import { MessagesModule } from './messages/messages.module';
import * as path from 'path';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: process.env.NODE_ENV === 'test' ? '.env.test' : '.env',
      ignoreEnvFile: process.env.NODE_ENV === 'production',
    }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (configService: ConfigService): TypeOrmModuleOptions => {
        const nodeEnv = configService.get<string>('NODE_ENV');
        const dbUrl = configService.get<string>('DATABASE_URL');

        console.log(`[AppModule] Running in NODE_ENV: ${nodeEnv}`);
        let dbUrlDisplay = 'No, it is undefined or not a string';
        if (dbUrl && typeof dbUrl === 'string') {
          const atIndex = dbUrl.indexOf('@');
          const endIndex =
            atIndex !== -1 ? atIndex : Math.min(30, dbUrl.length);
          dbUrlDisplay = `Yes, value starts with: ${dbUrl.substring(0, endIndex)}...`;
        }
        console.log(`[AppModule] DATABASE_URL loaded: ${dbUrlDisplay}`);

        const isProduction = nodeEnv === 'production';

        if (isProduction && !dbUrl) {
          console.error(
            '❌ [AppModule] FATAL ERROR: DATABASE_URL environment variable is NOT SET in production!',
          );
          throw new Error(
            'FATAL ERROR: DATABASE_URL environment variable is NOT SET in production!',
          );
        }

        let typeOrmOptions: Partial<TypeOrmModuleOptions>; // Partial yaptık, type sonra eklenecek

        if (dbUrl && typeof dbUrl === 'string') {
          typeOrmOptions = {
            url: dbUrl,
            ssl: dbUrl.includes('sslmode=require')
              ? { rejectUnauthorized: false }
              : undefined,
          };
        } else {
          console.warn(
            '[AppModule] DATABASE_URL not found or not a string, using individual DB parameters from .env for local development...',
          );
          typeOrmOptions = {
            host: configService.get<string>('DATABASE_HOST') || 'localhost',
            port: parseInt(
              configService.get<string>('DATABASE_PORT') || '5433',
              10,
            ),
            username: configService.get<string>('DATABASE_USER'),
            password: configService.get<string>('DATABASE_PASSWORD'),
            database: configService.get<string>('DATABASE_DB_NAME'),
            ssl: false,
          };
        }

        return {
          type: 'postgres', // type'ı buraya taşıdık
          ...typeOrmOptions,
          entities: [
            Message,
            // Diğer entity'leriniz buraya eklenecek
            // path.join(__dirname, '..', '**', '*.entity.{ts,js}') // Glob deseni alternatifi
          ],
          synchronize: false, // <<< HER ZAMAN FALSE!
          logging: ['error', 'warn', 'query'],
          migrations: [
            path.join(
              __dirname,
              '..',
              'database',
              'migrations',
              '*.{ts,js,sql}',
            ), // ../ ile src'den çıkıp database/migrations'a gidiyoruz
          ],
          migrationsRun: false, // Uygulama başlarken migration'ları otomatik ÇALIŞTIRMA
        };
      },
    }),
    MessagesModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
