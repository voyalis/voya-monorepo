import { Test, TestingModule } from '@nestjs/testing';
import { MessagesController } from './messages.controller';
import { MessagesService, CreateMessageDto } from './messages.service';
import { Message } from './message.entity';

const mockMessagesService = {
  create: jest.fn(),
  findAll: jest.fn(),
};

describe('MessagesController', () => {
  let controller: MessagesController;
  let service: MessagesService; // Bu değişken için uyarı alıyordunuz

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [MessagesController],
      providers: [
        {
          provide: MessagesService,
          useValue: mockMessagesService,
        },
      ],
    }).compile();

    controller = module.get<MessagesController>(MessagesController);
    service = module.get<MessagesService>(MessagesService); // Mock servisi al
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
    expect(service).toBeDefined(); // 'service' için uyarıyı gidermek amacıyla eklendi
    // Veya daha spesifik: expect(service.create).toBeDefined();
  });

  describe('create', () => {
    it('should create a message', async () => {
      const createDto: CreateMessageDto = { text: 'Test message' };
      const expectedResult: Message = {
        id: 'uuid', // Gerçek bir Message entity'si döndüğünü varsayıyoruz
        text: 'Test message',
        createdAt: new Date(),
      };
      mockMessagesService.create.mockResolvedValue(expectedResult);

      const result = await controller.create(createDto);

      expect(mockMessagesService.create).toHaveBeenCalledWith(createDto);
      expect(result).toEqual(expectedResult);
    });
  });

  describe('findAll', () => {
    it('should return an array of messages', async () => {
      const expectedResult: Message[] = [
        { id: 'uuid1', text: 'Msg1', createdAt: new Date() },
      ];
      mockMessagesService.findAll.mockResolvedValue(expectedResult);

      const result = await controller.findAll();

      expect(mockMessagesService.findAll).toHaveBeenCalled();
      expect(result).toEqual(expectedResult);
    });
  });
});
