OUTCOME_OK = 0
OUTCOME_SRQ = 1
OUTCOME_STUCK = 2


class AdbStuckError(Exception):
  '''Raised if the ADB is stuck low due to a misbehaving device.'''


class AdbTestHostError(Exception):
  '''Raised if the ADB test host does not return expected data.'''


class AdbTestHost:
  '''Represents an ADB test host.
  
  Note: serial_obj must have a timeout, though it should not be infinite.
  '''
  
  def __init__(self, serial_obj):
    self.serial_obj = serial_obj
    self.srq = False
  
  def reset(self):
    '''Effect a reset condition on the ADB.'''
    self.serial_obj.send_break()
  
  def sendreset(self):
    '''Send a SendReset command on the ADB.'''
    self.serial_obj.write(bytes((0x00,)))
    try:
      outcome = self.serial_obj.read(1)[0]
    except IndexError:
      raise AdbTestHostError('ADB host did not send outcome')
    if outcome == OUTCOME_STUCK: raise AdbStuckError()
    self.srq = True if outcome == OUTCOME_SRQ else False
  
  def flush(self, addr):
    '''Send a Flush command on the ADB to device at <addr>.'''
    if not 0 <= addr <= 15: raise ValueError('address must be 0-15')
    self.serial_obj.write(bytes(((addr << 4) | 0x01,)))
    try:
      outcome = self.serial_obj.read(1)[0]
    except IndexError:
      raise AdbTestHostError('ADB host did not send outcome')
    if outcome == OUTCOME_STUCK: raise AdbStuckError()
    self.srq = True if outcome == OUTCOME_SRQ else False
  
  def listen(self, addr, register, data):
    '''Send a Listen command with <data> to <register> of device at <addr>.'''
    if not 0 <= addr <= 15: raise ValueError('address must be 0-15')
    if not 0 <= register <= 3: raise ValueError('register must be 0-3')
    if not 2 <= len(data) <= 8: raise ValueError('data length must be 2-8')
    self.serial_obj.write(bytes(((addr << 4) | 0x08 | register, len(data))))
    self.serial_obj.write(data)
    try:
      outcome = self.serial_obj.read(1)[0]
    except IndexError:
      raise AdbTestHostError('ADB host did not send outcome')
    if outcome == OUTCOME_STUCK: raise AdbStuckError()
    self.srq = True if outcome == OUTCOME_SRQ else False
  
  def talk(self, addr, register):
    '''Send a Talk command to <register> of device at <addr>.'''
    if not 0 <= addr <= 15: raise ValueError('address must be 0-15')
    if not 0 <= register <= 3: raise ValueError('register must be 0-3')
    self.serial_obj.write(bytes(((addr << 4) | 0x0C | register,)))
    try:
      outcome = self.serial_obj.read(1)[0]
    except IndexError:
      raise AdbTestHostError('ADB host did not send outcome')
    try:
      length = self.serial_obj.read(1)[0]
    except IndexError:
      raise AdbTestHostError('ADB host did not send payload length')
    data = self.serial_obj.read(length)
    if len(data) != length: raise AdbTestHostError('ADB host did not return expected data length')
    if outcome == OUTCOME_STUCK: raise AdbStuckError()
    self.srq = True if outcome == OUTCOME_SRQ else False
    return data
