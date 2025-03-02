// Configuration
const CONFIG = {
    BACKEND_URL: 'http://localhost:8000',
    STUDENT_URL: 'http://localhost:5173',
    API_KEY: 'eyJ0IjoiMzU4NTFkYzEiLCJlIjoidGVvLmxvaHJlckBzb3Jib25uZS11bml2ZXJzaXRlLmZyIiwieCI6IjIwMjUwNTAzIn03LgypXGdPQ0Ls0E+2ETWz5Yfd0Npg1G1BoQ+mTpAfYo5yy/xNX9d029yV+3rdFu3N4aS1JflVhmdAkbzXnSMF'
};

document.addEventListener('DOMContentLoaded', function () {
    // Handle quiz containers
    const quizContainers = document.querySelectorAll('.quiz-container');

    quizContainers.forEach(function (container) {
        const createButton = container.querySelector('.create-quiz');
        const quizContent = container.querySelector('.quiz-content');
        const qrContainer = container.querySelector('.qr-container');
        const qrLinkContainer = container.querySelector('.qr-link-container');
        const title = container.dataset.title;
        const description = container.dataset.description;

        // Function to make authenticated API calls
        async function apiCall(endpoint, options = {}) {
            const headers = {
                'Content-Type': 'application/json',
                'api-key': CONFIG.API_KEY,
                ...options.headers
            };

            return fetch(`${CONFIG.BACKEND_URL}${endpoint}`, {
                ...options,
                headers
            });
        }

        createButton.addEventListener('click', async function () {
            createButton.disabled = true;
            createButton.textContent = 'Creating quiz session...';

            try {
                // Create new page on the server
                const response = await apiCall('/api/pages/', {
                    method: 'POST',
                    body: JSON.stringify({
                        title: title,
                        description: description
                    })
                });

                if (!response.ok) {
                    throw new Error(`Failed to create quiz page`);
                }

                const data = await response.json();
                const pageId = data.page_id;
                const joinUrl = `${CONFIG.STUDENT_URL}/?page=${pageId}`;

                // Generate QR code
                const qr = qrcode(0, 'L');
                qr.addData(joinUrl);
                qr.make();

                // Create and add QR code image
                const qrImage = document.createElement('div');
                qrImage.innerHTML = qr.createImgTag(5);
                qrContainer.appendChild(qrImage);

                // Display join URL as clickable link
                const urlLink = document.createElement('a');
                urlLink.href = joinUrl;
                urlLink.innerHTML = `
                    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path>
                        <polyline points="15 3 21 3 21 9"></polyline>
                        <line x1="10" y1="14" x2="21" y2="3"></line>
                    </svg>
                    Open quiz page
                `;
                urlLink.target = '_blank';
                qrLinkContainer.appendChild(urlLink);

                // Show quiz content
                quizContent.style.display = 'block';
                createButton.textContent = 'Quiz session created!';

                // Store the page ID in a global variable for questions to use
                window.currentQuizPageId = pageId;

            } catch (error) {
                console.error('Error setting up quiz:', error);
                createButton.disabled = false;
                createButton.textContent = 'Create Quiz Session';
            }
        });
    });

    // Handle question containers
    const questionContainers = document.querySelectorAll('.question-container');

    questionContainers.forEach(function (container) {
        const submitButton = container.querySelector('.submit-question');
        const closeButton = container.querySelector('.close-question');
        const answerCount = container.querySelector('.answer-count');
        const questionText = container.dataset.question;
        const options = JSON.parse(container.dataset.options);
        let pollInterval;

        // Function to make authenticated API calls
        async function apiCall(endpoint, options = {}) {
            const headers = {
                'Content-Type': 'application/json',
                'api-key': CONFIG.API_KEY,
                ...options.headers
            };

            return fetch(`${CONFIG.BACKEND_URL}${endpoint}`, {
                ...options,
                headers
            });
        }

        // Function to update answer count
        async function updateAnswerCount() {
            try {
                const response = await apiCall(`/api/pages/${window.currentQuizPageId}`);
                if (!response.ok) {
                    throw new Error('Failed to fetch page status');
                }

                const data = await response.json();
                const count = data.answers ? data.answers.length : 0;
                answerCount.textContent = `${count} ${count === 1 ? 'answer' : 'answers'}`;
            } catch (error) {
                console.error('Error fetching answer count:', error);
            }
        }

        // When submit button is clicked
        submitButton.addEventListener('click', async () => {
            if (!window.currentQuizPageId) {
                console.error('No active quiz page');
                return;
            }

            try {
                // Get the markdown versions of question and options
                const questionMarkdown = container.dataset.questionMarkdown || questionText;
                
                // Create a modified options array that uses markdown content
                const optionsWithMarkdown = options.map(option => ({
                    text: option.markdown || option.text, // Use markdown if available
                    is_correct: option.is_correct
                }));
                
                // Post the question to the server
                const response = await apiCall(`/api/pages/${window.currentQuizPageId}/questions`, {
                    method: 'POST',
                    body: JSON.stringify({
                        text: questionMarkdown, // Use markdown version
                        options: optionsWithMarkdown
                    })
                });

                if (!response.ok) {
                    throw new Error('Failed to post question');
                }

                // Show close button and answer count, disable submit button
                submitButton.disabled = true;
                closeButton.style.display = 'block';
                answerCount.style.display = 'inline-block';

                // Start polling for answer count
                updateAnswerCount();
                pollInterval = setInterval(updateAnswerCount, 2000);

            } catch (error) {
                console.error('Error submitting question:', error);
            }
        });

        // When close button is clicked
        closeButton.addEventListener('click', async () => {
            try {
                // Stop polling
                clearInterval(pollInterval);

                // Close the question via API
                const response = await apiCall(`/api/pages/${window.currentQuizPageId}/close-question`, {
                    method: 'POST'
                });

                if (!response.ok) {
                    throw new Error('Failed to close question');
                }

                const stats = await response.json();

                // Update each option with stats
                for (const [index, opt] of options.entries()) {
                    const optionStats = stats.option_stats[index];
                    const optionEl = container.querySelector(`.option[data-index="${index}"]`);
                    const statsEl = optionEl.querySelector('.option-stats');

                    // Update stats text
                    statsEl.textContent = `(${optionStats.count} / ${optionStats.percentage.toFixed(0)}%)`;

                    // Update styling
                    if (opt.is_correct) {
                        optionEl.classList.add('correct');
                    } else {
                        optionEl.classList.add('incorrect');
                    }
                }

                // Hide answer count and disable close button
                answerCount.style.display = 'none';
                closeButton.disabled = true;
                closeButton.textContent = 'Question Closed';

            } catch (error) {
                console.error('Error closing question:', error);
            }
        });
    });
});