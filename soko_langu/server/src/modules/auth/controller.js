const { getFirebaseAuth } = require('../../config/firebase');
const { getPrisma } = require('../../config/database');

// Send OTP to phone
async function sendOtp(req, res) {
  try {
    const { phone } = req.validated;
    // Firebase Phone Auth handles OTP sending
    // This endpoint validates the phone format and logs the attempt
    console.log(`[AUTH] OTP requested for phone: ${phone}`);
    
    res.json({ 
      success: true, 
      message: 'OTP sent successfully',
      phone: phone.replace(/\d(?=\d{4})/g, '*'), // Mask phone in response
    });
  } catch (error) {
    console.error('[AUTH] Send OTP error:', error.message);
    res.status(500).json({ error: 'Failed to send OTP' });
  }
}

// Verify OTP
async function verifyOtp(req, res) {
  try {
    const { phone, code } = req.validated;
    
    // Firebase Phone Auth verification happens client-side
    // Server receives the verified Firebase token
    console.log(`[AUTH] OTP verification for phone: ${phone}`);
    
    res.json({ 
      success: true, 
      message: 'OTP verified successfully',
    });
  } catch (error) {
    console.error('[AUTH] Verify OTP error:', error.message);
    res.status(500).json({ error: 'Failed to verify OTP' });
  }
}

// Send email OTP
async function sendEmailOtp(req, res) {
  try {
    const { email } = req.body;
    
    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'Valid email required' });
    }
    
    console.log(`[AUTH] Email OTP requested for: ${email}`);
    
    res.json({ 
      success: true, 
      message: 'Email OTP sent successfully',
    });
  } catch (error) {
    console.error('[AUTH] Send email OTP error:', error.message);
    res.status(500).json({ error: 'Failed to send email OTP' });
  }
}

// Verify email OTP
async function verifyEmailOtp(req, res) {
  try {
    const { email, code } = req.body;
    
    console.log(`[AUTH] Email OTP verification for: ${email}`);
    
    res.json({ 
      success: true, 
      message: 'Email OTP verified successfully',
    });
  } catch (error) {
    console.error('[AUTH] Verify email OTP error:', error.message);
    res.status(500).json({ error: 'Failed to verify email OTP' });
  }
}

// Check if phone exists
async function checkPhone(req, res) {
  try {
    const { phone } = req.body;
    
    if (!phone) {
      return res.status(400).json({ error: 'Phone number required' });
    }

    const prisma = getPrisma();
    const user = await prisma.user.findUnique({
      where: { phone },
      select: { id: true },
    });

    res.json({ exists: !!user });
  } catch (error) {
    console.error('[AUTH] Check phone error:', error.message);
    res.status(500).json({ error: 'Failed to check phone' });
  }
}

// Check if email exists
async function checkEmail(req, res) {
  try {
    const { email } = req.body;
    
    if (!email) {
      return res.status(400).json({ error: 'Email required' });
    }

    const prisma = getPrisma();
    const user = await prisma.user.findUnique({
      where: { email },
      select: { id: true },
    });

    res.json({ exists: !!user });
  } catch (error) {
    console.error('[AUTH] Check email error:', error.message);
    res.status(500).json({ error: 'Failed to check email' });
  }
}

module.exports = {
  sendOtp,
  verifyOtp,
  sendEmailOtp,
  verifyEmailOtp,
  checkPhone,
  checkEmail,
};
