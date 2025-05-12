// voya-monorepo/apps/api/src/messages/messages.service.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Message } from './message.entity';
import { IsNotEmpty, IsString, MinLength } from 'class-validator'; // Validasyon için

export class CreateMessageDto {
  @IsString()
  @IsNotEmpty()
  @MinLength(1)
  text: string;
}

@Injectable()
export class MessagesService {
  constructor(
    @InjectRepository(Message)
    private messagesRepository: Repository<Message>,
  ) {}

  async create(createMessageDto: CreateMessageDto): Promise<Message> {
    const newMessage = this.messagesRepository.create(createMessageDto);
    return this.messagesRepository.save(newMessage);
  }

  async findAll(): Promise<Message[]> {
    return this.messagesRepository.find();
  }
}
