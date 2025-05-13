import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service';

@Controller() // Global prefix'iniz 'api/v1' ise bu /api/v1 olur
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }

  @Get('health') // Bu endpoint /api/v1/health veya sadece /health olur
  health(): { status: string; timestamp: string; uptime?: string } {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: process.uptime ? `${process.uptime().toFixed(2)}s` : undefined,
    };
  }
}
